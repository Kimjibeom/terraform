# 1. Provider 설정
provider "vsphere" {
  user           = "administrator@vsphere.local"
  password       = "Insoft!23"
  vsphere_server = "172.30.10.3"

  # 자체 서명 인증서 사용 시 검증 무시
  allow_unverified_ssl = true
}

# 2. 데이터 소스
data "vsphere_datacenter" "dc" {
  name = "Datacenter" 
}

data "vsphere_datastore" "datastore" {
  name          = "local_10.12" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = "SW" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = "SW/Resources/ssg-dev" 
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network_1" {
  name          = "isolated_vSwitch" # 폐쇄망용 포트그룹 이름
  datacenter_id = data.vsphere_datacenter.dc.id
}

# 템플릿 정보 가져오기
data "vsphere_virtual_machine" "template" {
  name          = "temp_node"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# 3. VM 리소스 생성
resource "vsphere_virtual_machine" "vm" {
  count = 1 # VM 생성 대수

  # VM 이름: ssg-01 ~ ssg-0*
  name             = "ssg-${format("%02d", count.index + 1)}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  # 템플릿의 CPU/RAM 스펙을 그대로 사용
  num_cpus = data.vsphere_virtual_machine.template.num_cpus
  memory   = data.vsphere_virtual_machine.template.memory
  guest_id = data.vsphere_virtual_machine.template.guest_id

  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout  = 5

  # 폐쇄망용 NIC (172.30.31.x)
  network_interface {
    network_id   = data.vsphere_network.network_1.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  # 템플릿 복제 및 OS 설정
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = "ssg-${format("%02d", count.index + 1)}"
        domain    = "local"
      }

      # 첫 번째 NIC 설정 (172.30.31.111 ~ 11*)
      network_interface {
        ipv4_address = "172.30.31.${111 + count.index}"
        ipv4_netmask = 24
      }

      # 기본 게이트웨이
      ipv4_gateway = "172.30.0.1" 
    }
  }
}