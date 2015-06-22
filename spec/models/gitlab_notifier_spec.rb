require 'spec_helper'

describe 'GitlabNotifier URL parser' do

  giturl = Regexp.new '((?<scheme>[a-z]+)://)?((?<user>[a-z]+)@)?(?<host>[^:/]+)(:(?<port>[0-9]+))?([/:])?(?<path>(?<namespace>[^/]+)/(?<reponame>[^.]+)(.git)?.*)'

  [
    "git@github.com:javiplx/jenkins-gitlab-hook-plugin.git",
    "https://github.com/javiplx/jenkins-gitlab-hook-plugin.git",
    "ssh://git@github.com/javiplx/jenkins-gitlab-hook-plugin.git",
    "ssh://git@github.com:1234/javiplx/jenkins-gitlab-hook-plugin.git",
    "ssh://github.com/javiplx/jenkins-gitlab-hook-plugin.git",
    "ssh://github.com:1234/javiplx/jenkins-gitlab-hook-plugin.git"
  ].each do |url|
    context "parses #{url}" do
      urlmatch = giturl.match url
      it { expect(urlmatch['host']).to eq 'github.com' }
      it { expect(urlmatch['namespace']).to eq 'javiplx' }
      it { expect(urlmatch['reponame']).to eq 'jenkins-gitlab-hook-plugin' }
    end
  end

end

