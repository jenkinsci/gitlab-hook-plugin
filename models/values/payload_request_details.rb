require_relative 'request_details'

module GitlabWebHook
  class PayloadRequestDetails < RequestDetails
    def initialize(payload)
      @payload = payload || raise(ArgumentError.new("request payload is required"))
      @kind = payload['object_kind'].nil? ? 'webhook' : payload['object_kind']
    end

    def valid?
      [ 'push' , 'tag_push' ].include?(kind) or super
    end

    def repository_url
      if payload["project"] && payload["project"]["git_http_url"]
        payload["project"]["git_http_url"].strip
      elsif payload["repository"] && payload["repository"]["url"]
        payload["repository"]["url"].strip
      else
        ""
      end
    end

    def repository_group
      return "" unless repository_homepage
      repository_homepage.split('/')[-2]
    end

    def repository_name
      if payload["project"] && payload["project"]["name"]
        payload["project"]["name"].strip
      elsif payload["repository"] && payload["repository"]["name"]
        payload["repository"]["name"].strip
      else
        ""
      end
    end

    def repository_homepage
      if payload["project"] && payload["project"]["homepage"]
        payload["project"]["homepage"].strip
      elsif payload["repository"] && payload["repository"]["homepage"]
        payload["repository"]["homepage"].strip
      else
        ""
      end
    end

    def full_branch_reference
      if payload["ref"]
        payload["ref"].to_s.strip
      elsif payload["changes"] && payload["changes"][0] && payload["changes"][0]["ref"]
        payload["changes"][0]["ref"].strip
      else
        ""
      end
    end

    def delete_branch_commit?
      after = payload["after"]
      after ? (after.strip.squeeze == "0") : false
    end

    private

    def get_commits
      @commits ||= payload["commits"].to_a.map do |commit|
        Commit.new(commit["url"], commit["message"])
      end
    end

    def get_payload
      @payload
    end
  end
end
