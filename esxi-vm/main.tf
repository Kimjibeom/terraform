###############################################################################
# Terraform + vSphere Provider — ESXi 단일 호스트 OVF 기반 VM 배포
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Provider: ESXi 직접 연결 (vCenter 없음)
# ─────────────────────────────────────────────────────────────────────────────
provider "vsphere" {
  user                 = var.esxi_user
  password             = var.esxi_password
  vsphere_server       = var.esxi_host
  allow_unverified_ssl = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Data Sources: ESXi 호스트의 기본 인프라 정보
# ─────────────────────────────────────────────────────────────────────────────

# 단일 ESXi 호스트는 기본 데이터센터 "ha-datacenter"를 사용
data "vsphere_datacenter" "dc" {
  name = "ha-datacenter"
}

data "vsphere_host" "host" {
  name          = var.esxi_host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Pool (ESXi 단일 호스트는 호스트의 기본 리소스 풀 사용)
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# OVF 파일에서 VM 설정 읽기
# ─────────────────────────────────────────────────────────────────────────────
data "vsphere_ovf_vm_template" "ovf" {
  name              = "rocky9-template"
  resource_pool_id  = data.vsphere_host.host.resource_pool_id
  datastore_id      = data.vsphere_datastore.datastore.id
  host_system_id    = data.vsphere_host.host.id

  # OVF/OVA 파일 경로 (로컬 파일 또는 URL)
  local_ovf_path    = var.ovf_path     # 로컬 OVF 파일 경로
  # remote_ovf_url  = var.ovf_url      # 원격 URL 사용 시 이쪽으로 전환

  ovf_network_map = {
    "VM Network" = data.vsphere_network.network.id
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VM 배포 (for_each로 여러 VM 동시 배포)
# ─────────────────────────────────────────────────────────────────────────────
resource "vsphere_virtual_machine" "vm" {
  for_each = var.vms

  name             = each.key
  resource_pool_id = data.vsphere_host.host.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  host_system_id   = data.vsphere_host.host.id
  datacenter_id    = data.vsphere_datacenter.dc.id

  # 리소스 설정 — OVF 이미지 스펙에 맞게 each.value에서 가져옴
  num_cpus = each.value.cpu
  memory   = each.value.memory   # MB 단위

  # OVF에서 가져온 기본 설정
  guest_id             = data.vsphere_ovf_vm_template.ovf.guest_id
  firmware             = data.vsphere_ovf_vm_template.ovf.firmware
  scsi_type            = data.vsphere_ovf_vm_template.ovf.scsi_type
  num_cores_per_socket = data.vsphere_ovf_vm_template.ovf.num_cores_per_socket

  # 네트워크 인터페이스
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = "e1000"
  }

  # (disk 블록은 OVF 배포 시 standalone ESXi에서 정책 오류를 유발할 수 있으므로 제거. 원본 OVF의 디스크 설정을 그대로 따름)

  # OVF 배포 설정
  ovf_deploy {
    local_ovf_path    = var.ovf_path
    # remote_ovf_url  = var.ovf_url
    disk_provisioning = "thin"
    ovf_network_map = {
      "VM Network" = data.vsphere_network.network.id
    }
  }

  # (vApp 속성 설정은 ESXi 단일 호스트에서 지원되지 않아 에러를 유발하므로 제거함)

  # 네트워크 대기 해제 - IP 수동 설정을 위해
  wait_for_guest_net_timeout  = 0
  wait_for_guest_ip_timeout   = 0

  lifecycle {
    ignore_changes = [
      ovf_deploy,       # 초기 배포 이후 변경 무시
    ]
  }
}
