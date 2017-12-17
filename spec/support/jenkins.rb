require 'jenkins/plugin/specification'
require 'jenkins/plugin/tools/server'

require 'net/http'
require 'rexml/document'

require 'tmpdir'
require 'fileutils'

class Jenkins::Server

  attr_reader :workdir
  attr_reader :job, :std, :log

  REQUIRED_CORE = '1.651.3'

  def initialize

    version = ENV['JENKINS_VERSION'] || REQUIRED_CORE

    FileUtils.mkdir_p 'vendor/bundle'
    warname = "vendor/bundle/jenkins-#{version}.war"

    download_war( version , warname )

    @workdir = Dir.mktmpdir 'work'

    spec = Jenkins::Plugin::Specification.load('jenkins-gitlab-hook.pluginspec')
    server = Jenkins::Plugin::Tools::Server.new(spec, workdir, warname, '8080')

    # Dependencies for git 2.0
    FileUtils.mkdir_p "#{workdir}/plugins"
    unless version.split('.').first == '1'
      download_plugin 'credentials', '1.16.1', "#{workdir}/plugins"
      download_plugin 'ssh-credentials', '1.7.1', "#{workdir}/plugins"
      download_plugin 'matrix-project', '1.4.1', "#{workdir}/plugins"
      download_plugin 'script-security', '1.13', "#{workdir}/plugins"
      download_plugin 'junit', '1.2', "#{workdir}/plugins"
      download_plugin 'mailer', '1.11', "#{workdir}/plugins"
      download_plugin 'matrix-auth', '1.1', "#{workdir}/plugins"
    end

    download_plugin 'scm-api', '0.1', "#{workdir}/plugins"
    download_plugin 'git-client', '1.4.4', "#{workdir}/plugins"
    download_plugin 'ssh-agent', '1.3', "#{workdir}/plugins"
    download_plugin 'multiple-scms', '0.4', "#{workdir}/plugins"

    FileUtils.cp_r Dir.glob('work/*'), workdir

    @std, out = IO.pipe
    @log, err = IO.pipe
    @job = fork do
      $stdout.reopen out
      $stderr.reopen err
      ENV['JAVA_OPTS'] = "-XX:MaxPermSize=512m -Xms512m -Xmx1024m -Djruby.compile.mode=OFF -Djruby.objectspace.enabled=false"
      server.run!
    end
    Process.detach job

    begin
      line = log.readline
      puts " -> #{line}" if ENV['DEBUG']=='YES'
    end until line.include?('Jenkins is fully up and running')


  end

  def kill
    Process.kill 'TERM', job
    dump log, ' -> ' if ENV['DEBUG']=='YES'
    Process.waitpid job, Process::WNOHANG
  rescue Errno::ECHILD => e
  ensure
    if ENV['DEBUG']=='YES'
      Dir["#{workdir}/jobs/*/builds/?/log"].each do |file|
        puts
        puts "## #{file} ##"
        puts File.read(file)
      end
      Dir["#{workdir}/jobs/*/builds/?/build.xml"].each do |file|
        puts
        puts "## #{file} ##"
        puts File.read(file)
      end
    end
    FileUtils.rm_rf workdir
  end

  def result(name, seq)
    waittime = 30
    begin
      sleep 5
      uri = URI "http://localhost:8080/job/#{name}/#{seq}/api/json"
      response = JSON.parse Net::HTTP.get uri
      break if response['building'].is_a? FalseClass
    end until (waittime-=5).zero?
    response['result']
  end

  private

  def dump(instream, prefix='', outstream=$stdout)
    begin
      line = instream.readline
      outstream.puts "#{prefix}#{line}"
    end until instream.eof?
  end

end
