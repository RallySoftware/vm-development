module Rally
  module Mixin
    module VappParams
      def vapp_name
        @vapp_spec[:name]
      end

      def is_ci?
        ! ENV['BUILD_NUMBER'].to_s.empty?
      end

      def vapp_ci_name
        "#{vapp_name}-#{ENV['BUILD_NUMBER'] || 'dev'}"
      end

      def vapp_ci_test_name
        ENV['SPEC_VAPP'] || "#{vapp_ci_name}-test"
      end

      def vapp_ci_folder_name
        ENV['VAPP_CI_FOLDER_NAME'] || '/vApp_CI'
      end

      def vapp_last_tested_name
        "#{vapp_name}-lastTested"
      end

      def vapp_last_failed_name
        "#{vapp_name}-lastFailedBuild"
      end

      def vapp_release_name
        ENV['VAPP_RELEASE_NAME'] || "#{vapp_name}-lastSuccessfulBuild"
      end

      def vapp_release_folder_name
        ENV['VAPP_RELEASE_FOLDER_NAME'] || '/RallyVM'
      end
    end
  end
end

include Rally::Mixin::VappParams
