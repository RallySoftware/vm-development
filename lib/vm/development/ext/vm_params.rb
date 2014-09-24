require 'chef-vault'

module Rally
  module Mixin
    module VmParams
      def vm_name
        ENV['VM_NAME']
      end

      def vm_runlist
        ENV['VM_RUNLIST']
      end

      def vm_base_template
        ENV['VM_BASE_TEMPLATE'] || '/Templates/c65.medium'
      end

      def vm_ci_name
        "#{vm_name}-#{ENV['BUILD_NUMBER'] || 'dev'}"
      end

      def vm_ci_test_name
        ENV['SPEC_VM'] || "#{vm_ci_name}-test"
      end

      def vm_ci_folder_name
        ENV['VM_CI_FOLDER_NAME'] || '/Template CI'
      end

      def vm_last_tested_name
        "#{vm_name}-lastTested"
      end

      def vm_last_failed_name
        "#{vm_name}-lastFailedBuild"
      end

      def vm_release_name
        ENV['VM_RELEASE_NAME'] || "#{vm_name}-lastSuccessfulBuild"
      end

      def vm_release_folder_name
        ENV['VM_RELEASE_FOLDER_NAME'] || '/RallyVM'
      end

      def vm_ssh_password
        ENV['VM_SSH_PASSWORD']
      end

      def vm_vault_password(vault = ENV['VM_VAULT'].to_s)
        return vm_ssh_password if vault.empty?

        knife_home = ENV['KNIFE_HOME'] || "#{ENV['HOME']}/.chef"
        ChefVault.load_config("#{knife_home}/knife.rb")
        item = ChefVault::Item.load(vault, 'spec_user')
        item['user']['password'].to_s.strip
      end
    end
  end
end

include Rally::Mixin::VmParams