require 'spec_helper'

module GitlabWebHook
  describe Commit do
    let(:subject) { Commit.new('http://localhost/diaspora/diaspora/commits/450d0de7532f', 'Update Catalan translation', 'John Doe') }

    it 'has commit url' do
      expect(subject).to respond_to(:url)
      expect(subject.url).to eq('http://localhost/diaspora/diaspora/commits/450d0de7532f')
    end

    it 'has commit message' do
      expect(subject).to respond_to(:message)
      expect(subject.message).to eq('Update Catalan translation')
    end

    it 'has author name' do
      expect(subject).to respond_to(:author_name)
      expect(subject.author_name).to eq('John Doe')
    end

  end
end
