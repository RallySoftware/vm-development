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

        vapp
      end

      def vapp_instance(vapp_id)
        vapp_path = "#{vapp_id[:folder]}/#{vapp_id[:name]}"
        monkey.vapp vapp_path
      end

      def destroy_if_exists(vapp_id)
        vapp = vapp_instance vapp_id
        vapp.destroy if vapp
      end

      def destroy(vapp_id)
        deploy_lastTested vapp_id
        destroy_if_exists vapp_id
      end

      def move(vapp_id, destination)
        destroy_if_exists destination
        vapp = vapp_instance vapp_id
        if vapp
          dest_folder = monkey.folder(destination[:folder])
          dest_folder.MoveIntoFolder_Task(:list => [vapp]).wait_for_completion unless vapp_id[:folder].nil? || vapp_id[:folder] == destination[:folder]
          vapp.Rename_Task(newName: destination[:name]).wait_for_completion unless vapp_id[:name].nil? || vapp_id[:name] == destination[:name]
        end
      end

      def deploy(vapp_id, destination)
        raise 'Name and/or folder need to be different for deployment.' if (vapp_id[:folder] == destination[:folder]) && (vapp_id[:name] == destination[:name])
        move vapp_id, destination
        deploy_lastTested vapp_id
        vapp_instance destination
      end

      def vapp_test_instance(vapp_id)
        vapp_instance(name: "#{vapp_id[:name]}-test", folder: vapp_id[:folder])
      end

      def deploy_lastTested(vapp_id)
        vapp = vapp_test_instance(vapp_id)
        if vapp
          move(
            {name: vapp.name, folder: vapp_id[:folder]},
            {name: "#{vapp_id[:prefix]}-lastTested", folder: vapp_id[:folder]}
            )
        end
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

    end
  end
end
