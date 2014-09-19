require 'vm/development/ext/vmonkey'

module VappDevelopment
  class VAppAssembler
    class << self
      def assemble(vapp_descriptor, opts={})
        opts = default_opts.merge(opts)

        spec = vapp_spec(vapp_descriptor)
        vapp = monkey.cluster.resourcePool.CreateVApp(spec)

        clone_vms(opts, vapp_descriptor, vapp)

        set_entity_config(opts, vapp_descriptor[:vms], vapp)

        set_network_properties(opts, vapp_descriptor, vapp) if vapp_descriptor[:network_properties]

        vapp
      end

      private

      def default_opts
        {
          working_folder: 'vApp_CI'
        }
      end

      def set_entity_config(opts, vms, vapp)
        default_vapp_config = {
          startAction: 'powerOn',
          stopAction: 'guestShutdown',
          waitingForGuest: true,
          startOrder: 1
        }

        entity_configs = []
        vms.each do |veem|
          vm = vapp.vm.find { |vm| vm.name == "#{vapp.name}-#{veem[:name]}" }
          entity_configs << (
            { key: vm }
            .merge(default_vapp_config)
            .merge(veem[:entityConfig])
            )
        end

        vapp.UpdateVAppConfig(spec: RbVmomi::VIM.VAppConfigSpec(entityConfig: entity_configs))
      end

      def clone_vms(opts, vapp_descriptor, vapp)
        vapp_descriptor[:vms].each do |vm|
          src_vm = monkey.vm! vm[:source]
          target_path = "#{vapp_descriptor[:ci_folder]}/#{vapp.name}/#{vapp.name}-#{vm[:name]}"
          target_vm = src_vm.clone_to(target_path)
          vm[:properties].each { |key,val| target_vm.property(key,val) }
        end
      end

      #vApp create helpers below ---------------------

      def vapp_spec(vapp_descriptor)
        {
          name:       vapp_descriptor[:ci_name],
          resSpec:    vapp_res_spec(vapp_descriptor),
          configSpec: vapp_config_spec(vapp_descriptor),
          vmFolder:   monkey.folder(vapp_descriptor[:ci_folder])
        }
      end

      def vapp_res_spec(vapp_descriptor)
        RbVmomi::VIM.ResourceConfigSpec({
          cpuAllocation: RbVmomi::VIM.ResourceAllocationInfo({
            expandableReservation: true,
            limit: -1,
            reservation: 0,
            shares: { level: "normal", shares: 4000 }
            }),
          memoryAllocation: RbVmomi::VIM.ResourceAllocationInfo({
            expandableReservation: true,
            limit: -1,
            reservation: 221,
            shares: { level: "normal", shares: 163840 }
            })
        })
      end

      def vapp_config_spec(vapp_descriptor)
        {
          annotation: vapp_descriptor[:annotation],
          property: property_spec(vapp_descriptor[:properties]),
          product: product_spec(vapp_descriptor[:product])
        }
      end

      def property_spec(properties)
        props = []
        properties.each do |key,value|
          value = value.join(',') if value.is_a?(Array)
          props << RbVmomi::VIM.VAppPropertySpec(
            operation: 'add',
            info: {
              key: key.to_sym.object_id,
              id: key,
              type: 'string',
              userConfigurable: false,
              defaultValue: value
            }
          )
        end
        props
      end

      def product_spec(product)
        [ RbVmomi::VIM.VAppProductSpec(info: product.merge({key: 0}), operation: 'add') ]
      end

      def set_network_properties(opts, vapp_descriptor, vapp)
        vapp.property :netmask,           nil, type: 'ip'
        vapp.property :default_gateway,   nil, type: 'ip'
        vapp.property :dns1,              nil, type: 'ip'
        vapp.property :dns2,              nil, type: 'ip'
        vapp.property :dns_search_domain, nil

        vapp_descriptor[:vms].each do |veem|
          vapp.property "ip_address_#{veem[:name]}".to_sym, nil, type: 'ip'

          vm = vapp.find_vm! "#{vapp.name}-#{veem[:name]}"
          vm.property :vm_name, nil, defaultValue: veem[:name], userConfigurable: false
        end

      end

    end
  end
end
