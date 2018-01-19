require_relative '../exceptions/not_found_exception'
require_relative '../exceptions/configuration_exception'
require_relative '../values/project'
require_relative '../services/get_jenkins_projects'
require_relative '../services/build_scm'
require_relative '../util/settings'
require_relative '../services/security'

java_import Java.hudson.model.AbstractProject
java_import Java.hudson.plugins.git.GitSCM
java_import Java.hudson.plugins.git.BranchSpec
java_import Java.hudson.plugins.git.UserRemoteConfig
java_import Java.hudson.plugins.git.UserMergeOptions
java_import Java.hudson.plugins.git.extensions.impl.PreBuildMerge

module GitlabWebHook
  class CreateProjectForBranch
    include Settings

    def initialize(get_jenkins_projects = GetJenkinsProjects.new, build_scm = BuildScm.new)
      @get_jenkins_projects = get_jenkins_projects
      @build_scm = build_scm
      @logger = Java.java.util.logging.Logger.getLogger(self.class.name)
    end

    def with(details)
      return if details.branch.empty?
      copy_from = get_project_to_copy_from(details)
      new_project_name = get_new_project_name(copy_from, details)
      @logger.warning( "Multiple-SCMs project #{copy_from} incompletelly copied onto #{new_project_name}" ) if copy_from.multiscm?
      new_project_scm = @build_scm.with(copy_from.matched_scm || copy_from.matching_scms.find.first, details)
      branch_project = nil

      Security.impersonate(ACL::SYSTEM) do
        branch_project = Java.jenkins.model.Jenkins.instance.copy(copy_from.jenkins_project, new_project_name)
        set_scm(branch_project, new_project_scm)
        branch_project.makeDisabled(false)
        branch_project.description = settings.description
        branch_project.save
      end

      Project.new(branch_project)
    end

    def from_template(template, details)
      return if details.branch.empty?
      copy_from = get_template_project(template)
      new_project_name = details.repository_name
      raise ConfigurationException.new("project #{new_project_name} already created from #{template}") unless @get_jenkins_projects.named(new_project_name).empty?
      @logger.warning( "Multiple-SCMs project #{copy_from} incompletelly copied onto #{new_project_name}" ) if copy_from.multiscm?
      modified_scm = @build_scm.with(copy_from.jenkins_project.getSCMs().find.first, details, true)
      branch_project = nil

      Security.impersonate(ACL::SYSTEM) do
        branch_project = Java.jenkins.model.Jenkins.instance.copy(copy_from.jenkins_project, new_project_name)
        set_scm(branch_project, modified_scm)
        branch_project.makeDisabled(false)
        branch_project.save
      end

      Project.new(branch_project)
    end

    def for_merge(details)
      get_candidate_projects(details).collect do |copy_from|
        new_project_name = "#{copy_from.name}-mr-#{details.safe_branch}"
        @logger.warning( "Multiple-SCMs project #{copy_from} incompletelly copied onto #{new_project_name}" ) if copy_from.multiscm?
        cloned_scm = @build_scm.with(copy_from.matched_scm || copy_from.matching_scms.find.first, details)
        # What about candidates with pre-build merge enabled?
        user_merge_options = UserMergeOptions.new('origin', details.target_branch, 'default')
        cloned_scm.extensions.add PreBuildMerge.new(user_merge_options)
        new_project = nil

        Security.impersonate(ACL::SYSTEM) do
          new_project = Java.jenkins.model.Jenkins.instance.copy(copy_from.jenkins_project, new_project_name)
          set_scm(new_project, cloned_scm)
          new_project.makeDisabled(false)
          new_project.description = settings.description
          new_project.save
        end

        Project.new(new_project)
      end
    end

    private

    def get_project_to_copy_from(details)
      master_not_found_message = 'could not determine master project, please create a project for the repo (usually for the master branch)'
      @get_jenkins_projects.master(details) || raise(NotFoundException.new(master_not_found_message))
    end

    def get_template_project(template)
      candidates = @get_jenkins_projects.named(template)
      raise NotFoundException.new("could not found template '#{template}'") if candidates.empty?
      candidates.first
    end

    def get_candidate_projects(details)
      not_found_message = "could not find candidate for #{details.repository_name}::#{details.branch}"
      @get_jenkins_projects.matching_uri(details).select do |project|
        project.matches?(details, details.target_branch, true)
      end || raise(NotFoundException.new(not_found_message))
    end

    def get_new_project_name(copy_from, details)
      new_project_name = "#{settings.use_master_project_name? ? copy_from.name : details.repository_name}_#{details.safe_branch}"
      raise ConfigurationException.new("project #{new_project_name} already exists") unless @get_jenkins_projects.named(new_project_name).empty?
      new_project_name
    end
    
    def set_scm(project, scm)
      if project.java_kind_of?(AbstractProject)
        project.scm = scm
      else
        definition = Java.org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition.new(scm, project.definition.getScriptPath())
        project.definition = definition
      end
    end
    
  end
end
