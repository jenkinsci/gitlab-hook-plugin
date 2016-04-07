require_relative 'create_project_for_branch'
require_relative '../util/settings'

module GitlabWebHook
  class ProcessCommit
    include Settings

    def initialize
      @create_project_for_branch = CreateProjectForBranch.new
    end

    def with(details, projects, action)

      if projects.any?
        if settings.automatic_project_creation?
          projects.select! do |project|
            project.matches?(details, details.branch, true)
          end
          projects << @create_project_for_branch.with(details) if projects.empty?
        else
          projects.select! do |project|
            project.matches?(details)
          end
        end
      else
        search_templates(details, projects)
      end

      raise NotFoundException.new('no project references the given repo url and commit branch') unless projects.any?

      messages = []
      projects.each do |project|
        messages << action.call(project, details)
      end
      messages
    end

    private

    def search_templates(details, projects)
        settings.templated_jobs.each do |matchstr,template|
          if details.repository_name.start_with? matchstr
            projects << @create_project_for_branch.from_template(template, details)
          end
        end
        return if projects.any?
        settings.templated_descriptions.each do |matchstr,template|
          if details.repository_description.index matchstr
            projects << @create_project_for_branch.from_template(template, details)
          end
        end
        return if projects.any?
        settings.templated_groups.each do |matchstr,template|
          if details.repository_group == matchstr
            projects << @create_project_for_branch.from_template(template, details)
          end
        end
        return if projects.any?
        if settings.template_fallback
          projects << @create_project_for_branch.from_template(settings.template_fallback, details)
        end
    end
  end
end
