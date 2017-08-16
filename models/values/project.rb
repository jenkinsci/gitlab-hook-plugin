require 'forwardable'

require_relative '../exceptions/configuration_exception'
require_relative '../util/settings'
require_relative 'repository_uri'


include Java

java_import Java.hudson.model.AbstractProject
java_import Java.hudson.model.ParametersDefinitionProperty
java_import Java.hudson.model.StringParameterDefinition
java_import Java.hudson.model.ChoiceParameterDefinition
java_import Java.hudson.util.StreamTaskListener
java_import Java.hudson.util.NullStream
java_import Java.hudson.plugins.git.GitSCM
java_import Java.hudson.plugins.git.util.InverseBuildChooser
java_import Java.hudson.plugins.git.extensions.impl.PreBuildMerge
java_import Java.hudson.plugins.git.extensions.impl.RelativeTargetDirectory

MultipleScmsPluginAvailable = true
begin
  java_import Java.org.jenkinsci.plugins.multiplescms.MultiSCM
rescue NameError
  MultipleScmsPluginAvailable = false
end

module GitlabWebHook
  class Project
    BRANCH_NAME_PARAMETER_ACCEPTED_TYPES = [StringParameterDefinition, ChoiceParameterDefinition]

    include Settings
    extend Forwardable

    def_delegators :@jenkins_project, :schedulePolling, :scheduleBuild2, :fullName, :isParameterized, :isBuildable, :getQuietPeriod, :getProperty, :delete, :description

    alias_method :parametrized?, :isParameterized
    alias_method :buildable?, :isBuildable
    alias_method :name, :fullName
    alias_method :to_s, :fullName

    attr_reader :jenkins_project, :scms, :logger
    attr_reader :matching_scms, :matched_scm, :matched_branch, :matched_refspecs

    def initialize(jenkins_project, env_vars = nil)
      raise ArgumentError.new("jenkins project is required") unless jenkins_project
      @jenkins_project = jenkins_project
      @logger = Java.java.util.logging.Logger.getLogger(self.class.name)
      @matched_refspecs = []
      setup_scms
      if env_vars
        repository_uri = RepositoryUri.new(env_vars['GIT_URL'])
        match_scms(repository_uri)
        # On merges, GIT_BRANCH is not set
        if env_vars.has_key? 'GIT_BRANCH'
          branch = env_vars['GIT_BRANCH'].split('/')[1..-1].join('/')
          match_scm(branch, "refs/heads/#{branch}") # exact or not? Account for the '*' instead of asterisk
        end
      end
    end

    def matches_uri?(details_uri)
      return false unless scms.any?
      matching_scms?(details_uri)
    end

    def matches?(details, branch = false, exactly = false)
      return false unless buildable?
      if merge_to?( branch || details.branch )
        logger.info("project #{self} merge target matches #{branch || details.branch}")
        return true
      end
      matches_branch?(details, branch, exactly)
    end

    def pre_build_merge?
      pre_build_merge ? true : false
    end

    def merge_to?(branch, is_mr = false)
      return false unless ( is_mr || settings.merged_branch_triggering? ) && pre_build_merge?
      merge_params = pre_build_merge.get_options
      merge_params.merge_target == branch
    end

    def ignore_notify_commit?
      scms.find { |scm| scm.isIgnoreNotifyCommit() }
    end

    def tag?
      if parametrized? && branch_param = get_branch_name_parameter
        branch_param.name.downcase == 'tagname'
      end
    end

    def get_branch_name_parameter
      branch_name_param = get_default_parameters.find do |param|
        scms.find do |scm|
          next unless scm.repositories.size > 0
          scm.branches.find do |scm_branch|
            scm_branch.name.match(/.*\$?\{?#{param.name}\}?.*/)
          end
        end
      end

      if branch_name_param && !BRANCH_NAME_PARAMETER_ACCEPTED_TYPES.any? { |type| branch_name_param.java_kind_of?(type) }
        logger.warning("only string and choice parameters for branch parameter are supported")
        return nil
      end

      branch_name_param
    end

    def get_default_parameters
      # @see jenkins.model.ParameterizedJobMixIn.getDefaultParametersValues used in hudson.model.AbstractProject
      getProperty(ParametersDefinitionProperty.java_class).getParameterDefinitions()
    end

    def merge_target
      return nil unless pre_build_merge?
      pre_build_merge.get_options.merge_target
    end

    def local_clone
      local = matching_scms.first.extensions.get RelativeTargetDirectory.java_class
      return local.relative_target_dir if local
    end

    def multiscm?
      @multiscm == true
    end

    private

    # Although matching_scms is populated in webhook and notifier contexts, the
    # simple selection of the SCM (first from matching list), might cause bad
    # notification behaviour in some strange corner cases
    def pre_build_merge
      @pre_build_merge ||= matching_scms.first.extensions.get PreBuildMerge.java_class
    end

    def matching_scms?(details_uri)
      match_scms(details_uri).any?
    end

    def match_scms(details_uri)
      @matching_scms ||= scms.select do |scm|
        scm.repositories.find do |repo|
          repo.getURIs().find do |project_repo_uri|
            details_uri.matches?(project_repo_uri)
          end
        end
      end
    end

    # Maybe all this stuff could get delegated to an SCM poll, but on the meantime
    # we need to clarify the behaviour. From the available BranchSpec tests on the
    # git plugin, we seen that when there is no slash on the branch specification,
    # the first token of the supplied string is discarded, thus producing a false
    # match when the string neither has a slash and is equal to the branchspec. And
    # when there is a slash on configured BranchSpec, an standard matching is done,
    # with no extra work on the supplied string.
    # This means that the git plugin expects the supplied branch to be always prefixed
    # with the remote name.
    # Adding 'remotes' or 'refs/remotes' to the string does not change the match
    # behaviour except when by chance the mismatching portion is discarded by git plugin.
    # The results obtained when using any kind of 'refs/' prefix on configured branchspec
    # lead us to supose that a simple ant-alike path wildcard matching is done among
    # the configured refspec and the supplied string, except for the removal of the first
    # path portion when refspec has no slash.
    #
    def match_scm(branch, refspec, exactly = false)
      @matched_scm = matching_scms.find do |scm|
        @matched_branch = scm.branches.find do |scm_branch|
          scm.repositories.find do |repo|
            # When BranchSpec seems to be a 'refs' style, we use the reference supplied by
            # gitlab, which is the reference on its local repository. In any other case, we
            # follow the classic gitlab-hook processing.
            if scm_branch.name.start_with?('refs/')
              token = refspec
            elsif scm_branch.name.start_with?('*/')
              token = "*/#{branch}"
            else
              # if scm_branch.name has no slash, repo.name will be filtered on 'matches' call,
              token = "#{repo.name}/#{branch}"
            end
            scm_refspecs = repo.getFetchRefSpecs().select { |scm_refspec| scm_refspec.matchSource(refspec) }
            matched_refspecs.concat(scm_refspecs)
            scm_branch_name = scm_branch.name.match('/') ? scm_branch.name : "#{repo.name}/#{scm_branch.name}"
            scm_refspecs.any? && (exactly ? scm_branch_name == token : scm_branch.matches(token))
          end
        end
      end
    end

    def matches_branch?(details, branch = false, exactly = false)
      refspec = details.full_branch_reference
      branch = details.branch unless branch

      match_scm(branch, refspec, exactly)

      if !matched_branch && parametrized?
        branch_param = get_branch_name_parameter
        if branch_param && branch_param.name.downcase == 'tagname'
          @matched_branch = branch_param if details.tagname
        elsif matched_refspecs.any?
          @matched_branch = branch_param unless details.tagname
        end
      end

      @matched_scm = matching_scms.find { |scm| scm.buildChooser.java_kind_of?(InverseBuildChooser) } unless matched_scm
      build_chooser = matched_scm.buildChooser if matched_scm
      build_chooser && build_chooser.java_kind_of?(InverseBuildChooser) ? matched_branch.nil? : !matched_branch.nil?
    end

    def setup_scms
      @scms = []
      if jenkins_project.java_kind_of?(AbstractProject)
        if jenkins_project.scm
          if jenkins_project.scm.java_kind_of?(GitSCM)
            @scms << jenkins_project.scm
          elsif MultipleScmsPluginAvailable && jenkins_project.scm.java_kind_of?(MultiSCM)
            @multiscm = true
            @scms.concat(jenkins_project.scm.getConfiguredSCMs().select { |scm| scm.java_kind_of?(GitSCM) })
          end
        end
      else
        if jenkins_project.getSCMs()
          @scms.concat(jenkins_project.getSCMs().select { |scm| scm.java_kind_of?(GitSCM) })
        end
      end
    end
  end
end
