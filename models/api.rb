require 'sinatra/base'
require 'json'

require_relative 'exceptions/bad_request_exception'
require_relative 'exceptions/configuration_exception'
require_relative 'exceptions/not_found_exception'
require_relative 'use_cases/process_commit'
require_relative 'use_cases/process_delete_commit'
require_relative 'use_cases/process_merge_request'
require_relative 'services/get_jenkins_projects'
require_relative 'services/parse_request'
require_relative 'services/check_git_details'

java_import Java.org.jruby.exceptions.RaiseException
java_import Java.hudson.model.Action

module GitlabWebHook
  class Api < Sinatra::Base

  java_import Java.java.util.logging.Level

    get '/ping' do
      'Gitlab Web Hook is up and running :-)'
    end

    notify_commit = lambda do
      process_projects Proc.new { |project| NotifyCommit.new(project).call }
    end
    get '/notify_commit', &notify_commit
    post '/notify_commit', &notify_commit

    build_now = lambda do
      process_projects Proc.new { |project, details| BuildNow.new(project).with(details) }
    end
    get '/build_now', &build_now
    post '/build_now', &build_now

    post '/build_now/:project_name' do
      get_jenkins_projects = GetJenkinsProjects.new
      if projects = get_jenkins_projects.named(params[:project_name])
        project = projects.first
        cause_builder = GetBuildCause.new
        actions_builder = GetBuildActions.new
        details = parse_request
        actions = [cause_builder.with(details)]
        if project.multibranchProject?
          actions.concat actions_builder.with(project, details)
        end
        project.scheduleBuild2(project.getQuietPeriod(), actions.to_java(Action))
      end
    end

    error = lambda do
      unknown_route
    end
    get '/*', &error
    post '/*', &error

    private

    def process_projects(action)
      details = parse_request

      if errors = CheckGitDetails.new.with(details)
        return errors
      end

      projects = GetJenkinsProjects.new.matching_uri details
      if details.kind == 'merge_request'
        messages = ProcessMergeRequest.new.with(details, projects)
      else
        messages = details.delete_branch_commit? ? ProcessDeleteCommit.new.with(details, projects) : ProcessCommit.new.with(details, projects, action)
      end
      logger.info(messages.join("\n"))
      messages.collect { |message| message.gsub("\n", '<br>') }.join("<br>")
    rescue BadRequestException => e
      logger.warning(e.message)
      status 400
      e.message.gsub("\n", '<br>')
    rescue NotFoundException => e
      logger.warning(e.message)
      status 404
      e.message.gsub("\n", '<br>')
    rescue => e
      logger.severe("#{e.message}\nStack trace:\n#{e.backtrace.join("\n")}")
      status 500
      [e.message, '', 'Stack trace:', e.backtrace].flatten.join('<br>')
    end

    def parse_request
      ParseRequest.new.from(params, request).tap do |details|
        msgs = [
            'gitlab web hook triggered for',
            '   - with payload:',
            JSON.pretty_generate(details.payload)
        ]
        msgs.insert( 1,
            "   - repo url: #{details.repository_url}",
            "   - branch: #{details.branch}",
        ) unless details.kind == 'merge_request'
        logger.info(msgs.join("\n"))
      end
    end

    def unknown_route
      message = [
          "Don't know how to process '/#{params[:splat].first}'",
          'Use one of the following:',
          '   - /ping',
          '   - /notify_commit',
          '   - /build_now',
          '   - /build_now/:project_name',
          'See https://github.com/elvanja/jenkins-gitlab-hook-plugin for details'
      ].join("\n")
      logger.warning(message)
      status 400
      message.gsub("\n", '<br>')
    end

    def logger
      @logger ||= Java.java.util.logging.Logger.getLogger(Api.class.name)
    end
  end
end
