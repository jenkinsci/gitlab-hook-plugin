module GitlabWebHook
  class Commit
    attr_reader :url, :message, :author_name

    def initialize(url, message, author_name)
      @url = url
      @message = message
      @author_name = author_name
    end
  end
end
