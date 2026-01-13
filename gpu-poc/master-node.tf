resource "vsphere_virtual_machine" "master" {
  count = 3
  name  = "gpu-master-${format("%02d", count.index + 4)}"

  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = data.vsphere_virtual_machine.template.num_cpus
  memory   = data.vsphere_virtual_machine.template.memory
  guest_id = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout  = 5

  network_interface {
    network_id   = data.vsphere_network.network_1.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = "gpu-master-${format("%02d", count.index + 4)}"
        domain    = "local"
      }
      network_interface {
        ipv4_address = "172.30.32.${111 + count.index}"
        ipv4_netmask = 16
      }
      ipv4_gateway = "172.30.0.1"
      dns_server_list = ["8.8.8.8"]
    }
  }
}