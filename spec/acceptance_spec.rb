require 'support/env'
require 'support/common'

require 'tmpdir'
require 'fileutils'

feature 'GitLab WebHook' do

  testrepodir = Dir.mktmpdir [ 'testrepo' , '.git' ]

  before(:all) do
    FileUtils.cp_r Dir.glob("spec/fixtures/testrepo.git/*"), testrepodir
  end

  after(:all) do
    FileUtils.remove_dir testrepodir
    FileUtils.rm_rf Dir.glob('work/jobs/testrepo*')
  end

  feature 'Template based creation' do

    scenario 'Finds fallback template' do
      visit '/'
      expect(page).to have_xpath("//table[@id='projectstatus']/tbody/tr[@id='job_simplejob']")
    end

    scenario 'Creates project from template' do
      incoming_payload 'first_push', testrepodir
      visit '/'
      expect(page).to have_xpath("//table[@id='projectstatus']/tbody/tr[@id='job_testrepo']")
    end

    scenario 'Builds a push to master branch' do
      File.write("#{testrepodir}/refs/heads/master", '6957dc21ae95f0c70931517841a9eb461f94548c')
      incoming_payload 'master_push', testrepodir
      sleep 30
      visit '/job/testrepo'
      expect(page).to have_xpath("//a[@href='/job/testrepo/2/']")
    end

  end

  feature 'Automatic project creation' do

    scenario 'Finds cloneable project' do
      visit '/'
      expect(page).to have_xpath("//table[@id='projectstatus']/tbody/tr[@id='job_testrepo']")
    end

    scenario 'Creates project for new branch' do
      incoming_payload 'branch_creation', testrepodir
      visit '/'
      expect(page).to have_xpath("//table[@id='projectstatus']/tbody/tr[@id='job_testrepo_feature_branch']")
    end

  end

end

