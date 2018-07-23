RSpec.shared_context 'settings' do
  let(:settings) { GitlabWebHookRootActionDescriptor.new }
  let(:jenkins_instance) { double(Java.jenkins.model.Jenkins) }

  before(:each) do
    allow(Java.jenkins.model.Jenkins).to receive(:instance) { jenkins_instance }
    allow(jenkins_instance).to receive(:descriptor) { settings }
    allow(settings).to receive(:merge_request_processing?) { true }
    allow(settings).to receive(:merged_branch_triggering?) { true }
    allow(settings).to receive(:use_http_urls?) { true }
    allow(settings).to receive(:ignore_users) { "user 1, user 2, user 3" }
  end
end