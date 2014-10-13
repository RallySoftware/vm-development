require 'rspec/core'
require 'tempfile'
require 'rspec/core/rake_task'
require 'vm/development/ext/shell_out'
require 'vm/development/ext/vmonkey'
require 'vm/development/ext/vm_params'

module VmDevelopment
  class BuildTasks < Rake::TaskLib
    attr_reader :project_dir

    def initialize
      @project_dir   = Dir.pwd
      yield(self) if block_given?
      define
    end

    def define
      namespace 'vm' do
        desc 'Checks your VM dev environment'
        task :lint do
          puts 'Checking your VM project parameters'
          fail "ENV['VM_NAME'] must be set.  (e.g. 'onprem-corevm')" if ENV['VM_NAME'].to_s.empty?
          fail "ENV['VM_RUNLIST'] must be set.  (e.g. 'onprem_corevm')" if ENV['VM_RUNLIST'].to_s.empty?
          fail "ENV['VM_SSH_PASSWORD'] must be set." if ENV['VM_SSH_PASSWORD'].to_s.empty?

          puts 'Checking your chef credentials'
          shell_out! 'knife node list >/dev/null'

          puts 'Checking your vSphere credentials'
          monkey.folder! '/'

          puts "Checking vSphere base template [#{vm_base_template}]"
          monkey.vm! vm_base_template

          puts "Checking vSphere CI folder [#{vm_ci_folder_name}]"
          monkey.folder! vm_ci_folder_name

          puts "Checking vSphere release folder [#{vm_release_folder_name}]"
          monkey.folder! vm_release_folder_name
        end

        desc "Builds [#{vm_ci_name}] and [#{vm_ci_test_name}]"
        task build: [:clean, :build_vm_ci, :clone_for_test]

        desc "Cleans [#{vm_ci_name}] and [#{vm_ci_test_name}]"
        task :clean do
          vm_ci_path = "#{vm_ci_folder_name}/#{vm_ci_name}"
          puts "Destroying #{vm_ci_path}..."
          vm_ci = monkey.vm vm_ci_path
          vm_ci.destroy if vm_ci

          vm_ci_test_path = "#{vm_ci_folder_name}/#{vm_ci_test_name}"
          puts "Destroying #{vm_ci_test_path}..."
          vm_ci_test = monkey.vm vm_ci_test_path
          vm_ci_test.destroy if vm_ci_test
        end

        def with_sshkey(vm_ip_address, &block)
          private_key_path = Dir::Tmpname.make_tmpname "#{Dir.tmpdir}/id_rsa-onprem", nil
          public_key_path = "#{private_key_path}.pub"
          shell_out! %Q{ssh-keygen -f #{private_key_path} -N "" -C "xyzzy#{vm_ci_name}"}
          # Add the SSH key for knife solo
          shell_out! %Q{knife ssh #{vm_ip_address} "mkdir -p ~/.ssh && echo '`cat #{public_key_path}`' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" -m --ssh-user root --ssh-password '#{vm_ssh_password}' --no-host-key-verify}
          yield private_key_path, public_key_path
        ensure
          # Clean up SSH key
          puts "Cleaning up keys..."
          FileUtils.rm private_key_path
          FileUtils.rm public_key_path
          rm_ssh_key_cmd = %Q{sed -i "/xyzzy/d" ~/.ssh/authorized_keys}
          shell_out! %Q{knife ssh "#{vm_ip_address}" 'echo Removing bootstrap key' -m --ssh-user root --ssh-password '#{vm_ssh_password}' --no-host-key-verify}
          shell_out! %Q{knife ssh "#{vm_ip_address}" '#{rm_ssh_key_cmd}' -m --ssh-user root --ssh-password '#{vm_ssh_password}' --no-host-key-verify}
          shell_out! %Q{knife ssh "#{vm_ip_address}" 'cat ~/.ssh/authorized_keys' -m --ssh-user root --ssh-password '#{vm_ssh_password}' --no-host-key-verify}
        end

        task :prepare do
          base_template = monkey.vm! vm_base_template
          puts "Cloning    #{vm_ci_folder_name}/#{vm_ci_name}..."
          vm_ci = base_template.clone_to "#{vm_ci_folder_name}/#{vm_ci_name}"
          vm_ci.annotation = vm_ci_name

          puts "Starting   #{vm_ci_folder_name}/#{vm_ci_name}..."
          vm_ci.start
          vm_ci.wait_for_port 22
          vm_ip_address = vm_ci.guest_ip

          puts "VM IP Address: #{vm_ip_address}"

          with_sshkey(vm_ip_address) do |private_key_path, public_key_path|
            # Bootstrap with knife solo and converge
            Dir.chdir('./cookbook') do
              shell_out! %Q{knife solo prepare "root@#{vm_ip_address}" -i #{private_key_path} --no-host-key-verify}
            end
          end
        end

        task :converge do
          vm_ci = monkey.vm! "#{vm_ci_folder_name}/#{vm_ci_name}"
          vm_ip_address = vm_ci.guest_ip
          with_sshkey(vm_ip_address) do |private_key_path, public_key_path|
            # Bootstrap with knife solo and converge
            Dir.chdir('./cookbook') do
              shell_out! %Q{knife ssh "#{vm_ip_address}" 'rm -f /var/chef/cache/chef-client-running.pid' -m -i #{private_key_path} --no-host-key-verify}
              cmd = %Q{knife solo cook "root@#{vm_ip_address}" -o '#{vm_runlist}' -i #{private_key_path} --no-host-key-verify}
              cmd << " #{ENV['DEBUG_VM_CONVERGE'].to_s}" if ENV['DEBUG_VM_CONVERGE']
              shell_out! cmd
            end
          end
        end

        task :finalize do
          vm_ci = monkey.vm! "#{vm_ci_folder_name}/#{vm_ci_name}"
          vm_ip_address = vm_ci.guest_ip
          Dir.chdir('./cookbook') do
            shell_out! %Q{knife solo clean "root@#{vm_ip_address}" --ssh-password '#{vm_vault_password}' --no-host-key-verify}
          end
          vm_ci.stop
          vm_ci.MarkAsTemplate
        end

        task build_vm_ci: ['vm:prepare', 'vm:converge', 'vm:finalize']

        task :clone_for_test do
          puts "Cloning    #{vm_ci_folder_name}/#{vm_ci_test_name}..."
          vm_ci = monkey.vm! "#{vm_ci_folder_name}/#{vm_ci_name}"
          vm_ci_test = vm_ci.clone_to! "#{vm_ci_folder_name}/#{vm_ci_test_name}"
          vm_ci_test.annotation = "[Test] #{vm_ci_test_name}"
          vm_ci_test.property :boot_for_test, 'true'
          vm_ci_test.start
          vm_ci_test.wait_for_port 22
          puts "Testing VM is available at #{vm_ci_test.guest_ip}"
        end

        desc "Run specs on [#{vm_ci_test_name}]"
        task :spec do
          vm_ci_test = monkey.vm! "#{vm_ci_folder_name}/#{vm_ci_test_name}"
          ENV['REMOTE_HOST'] = vm_ci_test.guest_ip
          ENV['SPEC_USER'] = 'root'
          ENV['SPEC_PASSWORD'] = vm_vault_password
          ret = RSpec::Core::Runner.run(['spec'])
          raise('specs failed') unless ret == 0
        end

        desc "Release [#{vm_ci_name}] to [#{vm_release_folder_name}/#{vm_release_name}]"
        task :release do
          puts "Releasing  #{vm_release_folder_name}/#{vm_release_name}..."
          vm_ci = monkey.vm! "#{vm_ci_folder_name}/#{vm_ci_name}"
          vm_ci.move_to! "#{vm_release_folder_name}/#{vm_release_name}"
        end

        desc "Create, test and release template [#{vm_name}]"
        task :ci do
          begin
            ['vm:lint', 'vm:build_vm_ci', 'vm:clone_for_test', 'vm:spec', 'vm:release'].each do |task|
              Rake::Task[task].invoke
            end
          ensure
            Rake::Task['vm:cleanup'].invoke
          end
        end

        desc "Deploy [#{vm_ci_test_name}] to [#{vm_last_tested_name}], and [#{vm_ci_name}] to [#{vm_last_failed_name}]"
        task :cleanup do
          # release the last tested VM to lastTested
          vm_ci_test = monkey.vm "#{vm_ci_folder_name}/#{vm_ci_test_name}"
          unless vm_ci_test.nil?
            puts "Releasing #{vm_ci_folder_name}/#{vm_last_tested_name}"
            vm_ci_test.move_to! "#{vm_ci_folder_name}/#{vm_last_tested_name}"
          end

          # release the last failed VM if it's still around
          vm_ci = monkey.vm "#{vm_ci_folder_name}/#{vm_ci_name}"
          unless vm_ci.nil?
            puts "Releasing #{vm_ci_folder_name}/#{vm_last_failed_name}"
            vm_ci.move_to! "#{vm_ci_folder_name}/#{vm_last_failed_name}"
          end
        end

        desc "List IPs of all running VMs related to [#{vm_release_name}]"
        task :ips do
          [
            "#{vm_release_folder_name}/#{vm_release_name}",
            "#{vm_ci_folder_name}/#{vm_ci_name}",
            "#{vm_ci_folder_name}/#{vm_ci_test_name}",
            "#{vm_ci_folder_name}/#{vm_last_tested_name}",
            "#{vm_ci_folder_name}/#{vm_last_failed_name}"
          ].each do |vm_path|
            vm = monkey.vm vm_path

            puts "#{vm.guest_ip} #{vm_path}" unless vm.nil? || vm.guest_ip.nil?
          end
        end

      end
    end
  end
end