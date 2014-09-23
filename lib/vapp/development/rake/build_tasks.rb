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
        task build: [:clean, :assemble, :clone_for_test]

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

        task :assemble do
          puts "Assembling #{vapp_ci_folder_name}/#{vapp_ci_name}..."
          VappDevelopment::VAppAssembler.assemble(@vapp_spec)
        end

        def range_to_use
          range_to_use = is_ci? ? @vapp_spec[:network_properties][:build_ci_test] : @vapp_spec[:network_properties][:build_dev_test]

          # what IP range is -lastTested using right now?
          lastTested = monkey.vapp "#{vapp_ci_folder_name}/#{vapp_last_tested_name}"
          if lastTested
            lastTested_ip = lastTested.vAppConfig.property.find { |p| p.props[:id].start_with? 'ip_address_' }
            if lastTested_ip
              lastTested_ip = lastTested.property lastTested_ip[:id]
              if lastTested_ip
                range_to_use.each do |k,v|
                  next unless k.to_s.start_with?('ip_address_')
                  return @vapp_spec[:network_properties][:build_alternate] if v == lastTested_ip
                end
              end
            end
          end

          return range_to_use
        end

        def apply_network_properties(vapp)
          return unless @vapp_spec[:network_properties]
          range = range_to_use
          vapp.property :netmask,           range[:netmask]
          vapp.property :default_gateway,   range[:default_gateway]
          vapp.property :dns1,              range[:dns1]
          vapp.property :dns2,              range[:dns2]
          vapp.property :dns_search_domain, range[:dns_search_domain]

          @vapp_spec[:vms].each do |veem|
            ip_address_vm = "ip_address_#{veem[:name]}".to_sym
            vapp.property ip_address_vm.to_sym, range[ip_address_vm]
          end
        end

        task :clone_for_test do
          puts "Cloning    #{vapp_ci_folder_name}/#{vapp_ci_test_name}"
          vapp_ci = monkey.vapp "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          vapp_ci_test = vapp_ci.clone_to "#{vapp_ci_folder_name}/#{vapp_ci_test_name}", vmFolder: vapp_ci.parentFolder

          vapp_ci_test.property(:boot_for_test, true)

          apply_network_properties(vapp_ci_test)

          puts "Starting   #{vapp_ci_folder_name}/#{vapp_ci_test_name}, waiting for port 22 on all VMs"
          vapp_ci_test.start
          vapp_ci_test.wait_for_port(22)
        end

        desc ''
        RSpec::Core::RakeTask.new(:rspec_assembly) do |task|
          task.pattern = 'spec/assembly'
        end

        desc ''
        RSpec::Core::RakeTask.new(:rspec_integration) do |task|
          task.pattern = 'spec/integration'
        end

        task :spec_assembly do
          ENV['VAPP_NAME'] ||= vapp_ci_name
          ENV['VAPP_FOLDER'] ||= vapp_ci_folder_name
          ENV['VMONKEY_YML'] ||= '~/.chef/vsphere.yml'
          puts "Running assembly specs on #{vapp_ci_folder_name}/#{vapp_ci_test_name}..."
          Rake::Task['vapp:rspec_assembly'].invoke
        end

        task :spec_integration do
          ENV['VAPP_NAME'] ||= vapp_ci_test_name
          ENV['VAPP_FOLDER'] ||= vapp_ci_folder_name
          ENV['VMONKEY_YML'] ||= '~/.chef/vsphere.yml'
          puts "Running integration specs on #{vapp_ci_folder_name}/#{vapp_ci_test_name}..."
          Rake::Task['vapp:rspec_integration'].invoke
        end

        desc "Run specs on [#{vapp_ci_test_name}]"
        task :spec => ['vapp:spec_assembly', 'vapp:spec_integration']

        desc "Release [#{vapp_ci_name}] to [#{vapp_release_folder_name}/#{vapp_release_name}]"
        task :release do
          puts "Releasing  #{vapp_release_folder_name}/#{vapp_release_name}..."
          vapp_ci = monkey.vapp! "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          vapp_ci.move_to! "#{vapp_release_folder_name}/#{vapp_release_name}"
        end

        desc "Build, test and release vApp [#{vapp_name}]"
        task :ci do
          begin
            ['vapp:lint', 'vapp:assemble', 'vapp:clone_for_test', 'vapp:spec', 'vapp:release'].each do |task|
              Rake::Task[task].invoke
            end
          ensure
            Rake::Task['vapp:cleanup'].invoke
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
          vapp_ci = monkey.vapp "#{vapp_ci_folder_name}/#{vapp_ci_name}"
          unless vapp_ci.nil?
            puts "Releasing #{vapp_ci_folder_name}/#{vapp_last_failed_name}"
            vapp_ci.move_to! "#{vapp_ci_folder_name}/#{vapp_last_failed_name}"
          end
        end

        desc "List assigned IPs of all running VMs related to [#{vapp_release_name}]"
        task :ips do
          [
            "#{vapp_release_folder_name}/#{vapp_release_name}",
            "#{vapp_ci_folder_name}/#{vapp_ci_name}",
            "#{vapp_ci_folder_name}/#{vapp_ci_test_name}",
            "#{vapp_ci_folder_name}/#{vapp_last_tested_name}",
            "#{vapp_ci_folder_name}/#{vapp_last_failed_name}"
          ].each do |vapp_path|
            vapp = monkey.vapp vapp_path
            next unless vapp

            vapp.vAppConfig.property.find_all { |p| p.props[:id].start_with? 'ip_address_' }.each do |ip_prop|
              ip = vapp.property ip_prop[:id]
              puts "[ #{ip} ] #{vapp_path}/#{ip_prop[:id]}"
            end
          end
        end

      end
    end
  end
end
