###############################################################################
# 출력값 정의
###############################################################################

output "vm_info" {
  description = "배포된 VM 정보"
  value = {
    for name, vm in vsphere_virtual_machine.vm : name => {
      name       = vm.name
      ip         = var.vms[name].ip
      cpu        = vm.num_cpus
      memory_mb  = vm.memory
      guest_id   = vm.guest_id
    }
  }
}

output "vm_ips" {
  description = "VM 이름 → IP 매핑"
  value = {
    for name, config in var.vms : name => config.ip
  }
}
