# Terraform ESXi 6.0 VM Provisioning (Rocky Linux 9)

이 프로젝트는 vCenter가 없는 **단일 ESXi 호스트(버전 6.0)** 환경에서 Terraform을 사용하여 **Rocky Linux 9 가상머신(VM)을 OVF 템플릿 기반으로 자동 배포**하는 인프라 코드(IaC)입니다.

## 📌 주요 특징
- vCenter 없이 ESXi 호스트에 직접 연결하여 VM 프로비저닝 수행
- 미리 생성된 OVF/OVA 템플릿 이미지를 기반으로 배포 (Cloning 불필요)
- `for_each` 구문을 활용하여 다수의 VM을 손쉽게 스케일 아웃

## 📂 파일 구조
- `main.tf`: 프로바이더 설정 및 vSphere 리소스(`vsphere_virtual_machine`) 정의
- `variables.tf`: 프로젝트에서 사용하는 변수 선언
- `terraform.tfvars`: 실제 배포에 사용되는 설정값 (Git에서 제외 권장)
- `ovf/`: OVF 템플릿 파일이 위치하는 디렉토리 (예: `rocky9-template.ovf`)

---

## 🚀 사용 방법

### 1. 설정 파일 작성
`terraform.tfvars` 파일을 열고 본인의 환경에 맞게 값을 수정합니다.

```hcl
esxi_host     = "10.10.30.200"
esxi_user     = "root"
esxi_password = "esxi_password"
datastore     = "datastore1"

# 배포할 VM 목록 정의
vms = {
  "my-rocky9-vm01" = {
    cpu       = 4
    memory    = 8192
    disk_size = 50
    ip        = "10.10.30.231"
    netmask   = "24"
    gateway   = "10.10.30.250"
    dns       = ["8.8.8.8", "8.8.4.4"]
  }
}
```

### 2. 프로바이더 초기화 및 배포
최신(v2.x) vmware 프로바이더를 사용하여 인프라를 배포합니다. ESXi 6.0 호스트의 구형 암호화 통신(TLS RSA) 지원을 위해 `GODEBUG` 환경변수를 필수로 추가해야 합니다.

```bash
# 초기화 (최초 1회 또는 프로바이더 변경 시)
terraform init -upgrade

# 배포 실행
GODEBUG=tlsrsakex=1 terraform apply -auto-approve
```

---

## ⚠️ 알려진 제약 사항 및 수동 네트워크 설정 가이드

### 제약 사항 원인
단일 ESXi 6.0 환경 및 Rocky Linux 9 조합에서는 다음의 이유로 **Terraform을 통한 완벽한 원격 네트워크 IP 주입이 불가능**합니다.
1. **ESXi 6.0 API 버그**: vCenter가 없는 단일 호스트에서는 SPBM(디스크 정책) 에러로 인해 vApp 속성 주입이 실패하며, `guest.run` API도 동작하지 않습니다.
2. **SELinux 차단**: `guest.start`를 통한 강제 스크립트 실행은 성공하지만, Rocky 9의 강력한 기본 보안(SELinux Enforcing)이 외부 쉘 스크립트 실행을 악성 접근으로 간주하여 즉시 차단합니다.

### 수동 네트워크 설정 (필수)
VM 배포 완료(`Apply complete!`) 후, ESXi 콘솔을 통해 해당 VM에 로그인하여 아래 3개의 명령어를 직접 실행해야 합니다.

```bash
# 1. 기존의 잘못된 프로파일 삭제
nmcli con delete "System ens32"

# 2. 새로운 프로파일 생성 (Terraform 변수에 선언한 IP 값 반영)
nmcli con add type ethernet ifname ens32 con-name ens32 ipv4.method manual \
  ipv4.addresses 10.10.30.231/24 \
  ipv4.gateway 10.10.30.250 \
  ipv4.dns "8.8.8.8 8.8.4.4"

# 3. 인터페이스 활성화 및 확인
nmcli con up ens32
ip addr show
```
