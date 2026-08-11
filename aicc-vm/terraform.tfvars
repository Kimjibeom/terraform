###############################################################################
# terraform.tfvars — 실제 배포 값 정의
###############################################################################

esxi_host     = "10.10.40.243"
esxi_user     = "root"
esxi_password = "nexus2580"

datastore     = "datastore1"
network       = "VM Network"

ovf_path      = "/home/jbkim/terraform/esxi-vm/ovf/rocky9-template.ovf"

# ─────────────────────────────────────────────────────────────────────────────
# VM 목록 정의
# 이름(key)마다 개별 스펙과 IP를 지정합니다.
# 이미지 스펙에 맞게 cpu, memory, disk_size를 조절하세요.
# ─────────────────────────────────────────────────────────────────────────────
vms = {
  "jbkim_dev_44" = {
    cpu       = 2
    memory    = 8192       # 8 GB
    disk_size = 50         # 50 GB
    ip        = "10.10.40.44"
    netmask   = "24"
    gateway   = "10.10.40.250"
    dns       = ["8.8.8.8"]
  }

  "jbkim_dev_master02_45" = {
    cpu       = 4
    memory    = 8192    
    disk_size = 50        
    ip        = "10.10.40.45"
    netmask   = "24"
    gateway   = "10.10.40.250"
    dns       = ["8.8.8.8"]
  }

  "jbkim_dev_master03_46" = {
    cpu       = 4
    memory    = 8192    
    disk_size = 50        
    ip        = "10.10.40.46"
    netmask   = "24"
    gateway   = "10.10.40.250"
    dns       = ["8.8.8.8"]
  }

  "jbkim_dev_worker01_47" = {
    cpu       = 4
    memory    = 16384      # 16 GB
    disk_size = 100        # 100 GB
    ip        = "10.10.40.47"
    netmask   = "24"
    gateway   = "10.10.40.250"
    dns       = ["8.8.8.8"]
  }

  "jbkim_dev_worker02_48" = {
    cpu       = 4
    memory    = 16384      
    disk_size = 100        
    ip        = "10.10.40.48"
    netmask   = "24"
    gateway   = "10.10.40.250"
    dns       = ["8.8.8.8"]
  }

  "jbkim_dev_nfs_55" = {
    cpu       = 2
    memory    = 8192      
    disk_size = 50        
    ip        = "10.10.40.55"
    netmask   = "24"
    gateway   = "10.10.40.250"
    dns       = ["8.8.8.8"]
  }
}
