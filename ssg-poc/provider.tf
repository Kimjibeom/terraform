provider "vsphere" {
  user                 = "administrator@vsphere.local"
  password             = "Insoft!23"
  vsphere_server       = "172.30.10.3"
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" { name = "Datacenter" }

data "vsphere_datastore" "datastore" {
  name          = "CloudHQ_NAS03" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = "SW" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = "SW/Resources/ssg-poc" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network_1" {
  name          = "VM Network" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = "temp_node"
  datacenter_id = data.vsphere_datacenter.dc.id
}