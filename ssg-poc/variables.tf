variable "vsphere_user" {
  description = "vSphere 사용자 이름"
  type        = string
  default     = "administrator@vsphere.local"
}

variable "vsphere_password" {
  description = "vSphere 비밀번호"
  type        = string
  sensitive   = true 
}

variable "vsphere_server" {
  description = "vSphere 서버 IP"
  type        = string
  default     = "172.30.10.3"
}
