require 'vm/development/ext/vmonkey'

module VappDevelopment
  class DeployTasks < Rake::TaskLib
    attr_reader :project_dir

    def initialize(deploy_spec)
      @project_dir   = Dir.pwd
      @deploy_spec = deploy_spec
      raise 'name not defined'   unless @deploy_spec[:name]
      raise 'source not defined' unless @deploy_spec[:source]
      raise 'target not defined' unless @deploy_spec[:target]
      yield(self) if block_given?
      define
    end

    def define
      namespace 'vapp' do
        namespace 'deploy' do
          desc "(Re)-Deploys #{@deploy_spec[:name]}"
          task @deploy_spec[:name] do
            source_path = @deploy_spec[:source]
            target_path = @deploy_spec[:target]
            puts "[#{@deploy_spec[:name]}] deploying [#{target_path}] from [#{source_path}]"

            source = monkey.vapp! source_path
            target = source.clone_to! target_path
            target.network = @deploy_spec[:network] if @deploy_spec[:network]
            target.set_properties @deploy_spec[:properties] if @deploy_spec[:properties]

            puts "[#{@deploy_spec[:name]}] starting and and waiting for port 22 on all VMs"
            target.start
            target.wait_for_port 22

            target.vm.each do |vm|
              puts "#{vm.guest_ip}\t#{vm.name}"
            end
            puts "[#{@deploy_spec[:name]}] deployed"
          end

          desc "Destroys #{@deploy_spec[:name]}"
          task "#{@deploy_spec[:name]}:destroy" do
            target_path = @deploy_spec[:target]
            target = monkey.vapp target_path
            if target
              puts "[#{@deploy_spec[:name]}] destroying [#{target_path}]"
              target.destroy
            else
              puts "[#{@deploy_spec[:name]}] nothing to destroy"
            end
          end
        end
      end
    end
  end
end
