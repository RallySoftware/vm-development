require 'vmonkey'

module Rally
  module Mixin
    module Vmonkey
      def monkey
        ENV['VMONKEY_YML'] ||= '~/.chef/vsphere.yml'
        @monkey ||= VMonkey.connect
      end
    end
  end
end

include Rally::Mixin::Vmonkey