require 'rspec/core'
require 'tempfile'
require 'rspec/core/rake_task'
require 'vm/development/ext/shell_out'
require 'vm/development/ext/vmonkey'
require 'vapp/development/ext/vapp_params'
require 'vapp/development/vapp_assembler'

module VappDevelopment
  class BuildTasks < Rake::TaskLib
    attr_reader :project_dir

    def initialize(vapp_spec)
      @project_dir   = Dir.pwd
      @vapp_spec = vapp_spec
      @vapp_spec[:annotation] ||= ""
      @vapp_spec[:vms] ||= []
      @vapp_spec[:annotation] << " #{vapp_ci_name}"
      @vapp_spec[:properties] ||= {}
      @vapp_spec[:properties][:build] ||= vapp_ci_name
      @vapp_spec[:ci_name] ||= vapp_ci_name
      @vapp_spec[:ci_folder] ||= vapp_ci_folder_name

      yield(self) if block_given?
      define
    end

    def define
      namespace 'vapp' do
        desc 'Checks your vApp dev environment'
        task :lint do
          puts 'Checking your vApp spec'
          fail "vapp_spec[:name] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:name].to_s.empty?
          fail "vapp_spec[:annotation] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:annotation].to_s.empty?
          fail "vapp_spec[:product] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:product].to_s.empty?
          fail "vapp_spec[:product][:name] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:product][:name].to_s.empty?
          fail "vapp_spec[:product][:productUrl] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:product][:productUrl].to_s.empty?
          fail "vapp_spec[:product][:vendor] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:product][:vendor].to_s.empty?
          fail "vapp_spec[:product][:vendorUrl] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:product][:vendorUrl].to_s.empty?
          fail "vapp_spec[:product][:version] must be set.  (e.g. 'onprem-corevm')" if @vapp_spec[:product][:version].to_s.empty?

          puts 'Checking your vSphere credentials'
          monkey.folder! '/'

          puts "Checking vSphere CI folder [#{vapp_ci_folder_name}]"
          monkey.folder! vapp_ci_folder_name

          puts "Checking vSphere release folder [#{vapp_release_folder_name}]"
          monkey.folder! vapp_release_folder_name
        end

        desc "Builds [#{vapp_ci_name}] and [#{vapp_ci_test_name}]"
        task build: [:clean, :build_vapp_ci, :clone_for_test]

        desc "Cleans [#{vapp_ci_name}] and [#{vapp_ci_test_name}]"
        task :clean do
          vapp_ci_path = "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          puts "Destroying #{vapp_ci_path}..."
          vapp_ci = monkey.vapp vapp_ci_path
          vapp_ci.destroy if vapp_ci

          vapp_ci_test_path = "#{vapp_ci_folder_name}/#{vapp_ci_test_name}"
          puts "Destroying #{vapp_ci_test_path}..."
          vapp_ci_test = monkey.vapp vapp_ci_test_path
          vapp_ci_test.destroy if vapp_ci_test
        end

        task :build_vapp_ci do
          puts "Assembling #{vapp_ci_folder_name}/#{vapp_ci_name}..."
          VappDevelopment::VAppAssembler.assemble(@vapp_spec)
        end

        task :clone_for_test do
          puts "Cloning    #{vapp_ci_folder_name}/#{vapp_ci_test_name}, waiting for port 22 on all VMs"
          vapp_ci = monkey.vapp "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          vapp_ci_test = vapp_ci.clone_to "#{vapp_ci_folder_name}/#{vapp_ci_test_name}", vmFolder: vapp_ci.parentFolder

          vapp_ci_test.property(:boot_for_test, true)
          vapp_ci_test.start
          vapp_ci_test.wait_for_ports(22)
        end

        desc "Run specs on [#{vapp_ci_test_name}]"
        task :spec do
        end

        desc "Release [#{vapp_ci_name}] to [#{vapp_release_folder_name}/#{vapp_release_name}]"
        task :release do
          puts "Releasing  #{vapp_release_folder_name}/#{vapp_release_name}..."
          vapp_ci = monkey.vapp! "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          vapp_ci.move_to! "#{vapp_release_folder_name}/#{vapp_release_name}"
        end

        desc "Create, test and release vApp [#{vapp_name}]"
        task :ci do
          begin
            ['vm:lint', 'vm:build_vapp_ci', 'vm:clone_for_test', 'vm:spec', 'vm:release'].each do |task|
              Rake::Task[task].invoke
            end
          ensure
            Rake::Task['vm:cleanup'].invoke
          end
        end

        desc "Deploy [#{vapp_ci_test_name}] to [#{vapp_last_tested_name}], and [#{vapp_ci_name}] to [#{vapp_last_failed_name}]"
        task :cleanup do
          # release the last tested vApp to lastTested
          vapp_ci_test = monkey.vapp! "#{vapp_ci_folder_name}/#{vapp_ci_test_name}"
          unless vapp_ci_test.nil?
            puts "Releasing #{vapp_ci_folder_name}/#{vapp_last_tested_name}"
            vapp_ci_test.move_to! "#{vapp_ci_folder_name}/#{vapp_last_tested_name}"
          end

          # release the last failed vApp if it's still around
          vapp_ci = monkey.vapp! "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          unless vapp_ci.nil?
            puts "Releasing #{vapp_ci_folder_name}/#{vapp_last_failed_name}"
            vapp_ci.move_to! "#{vapp_ci_folder_name}/#{vapp_last_failed_name}"
          end
        end
      end
    end
  end
end
