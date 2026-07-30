###############################################################################
# 변수 정의
###############################################################################

# ─── ESXi 접속 정보 ──────────────────────────────────────────────────────────
variable "esxi_host" {
  type        = string
  description = "ESXi 호스트 IP 주소"
  default     = "10.10.30.200"
}

variable "esxi_user" {
  type        = string
  description = "ESXi 로그인 사용자"
  default     = "root"
}

variable "esxi_password" {
  type        = string
  description = "ESXi 로그인 비밀번호"
  sensitive   = true
}

# ─── 인프라 설정 ──────────────────────────────────────────────────────────────
variable "datastore" {
  type        = string
  description = "ESXi 데이터스토어 이름"
  default     = "datastore1"
}

variable "network" {
  type        = string
  description = "ESXi 네트워크 이름"
  default     = "VM Network"
}

# ─── OVF 파일 경로 ───────────────────────────────────────────────────────────
variable "ovf_path" {
  type        = string
  description = "OVF 파일의 로컬 경로"
  default     = "./ovf/rocky9-template.ovf"
}

# ─── VM 정의 (for_each 맵) ───────────────────────────────────────────────────
variable "vms" {
  type = map(object({
    cpu       = number
    memory    = number     # MB
    disk_size = number     # GB
    ip        = string
    netmask   = string
    gateway   = string
    dns       = list(string)
  }))
  description = "배포할 VM 목록 (이름 → 스펙)"
}
