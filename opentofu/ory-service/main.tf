provider "aws" {
  region = "ap-northeast-2"
}

################################
# Networking
################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "main-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-gw" }
}

resource "aws_subnet" "public-01" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/20"
  map_public_ip_on_launch = true
  tags = { Name = "public_subnet-01" }
}

resource "aws_subnet" "public-02" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.16.0/20"
  map_public_ip_on_launch = true
  tags = { Name = "public_subnet-02" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public-01" {
  subnet_id      = aws_subnet.public-01.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public-02" {
  subnet_id      = aws_subnet.public-02.id
  route_table_id = aws_route_table.public.id
}

################################
# Security Groups
################################
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_ssh" }
}

# Grafana 3000/TCP
resource "aws_security_group" "allow_grafana_http" {
  name        = "allow_grafana_http"
  description = "Allow Grafana HTTP (3000)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Grafana HTTP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.grafana_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "allow_grafana_http" }
}

################################
# Locals: scripts as base64
################################
locals {
  kratos_script_b64 = base64encode(file("${path.module}/scripts/create_kratos_identity.sh"))
  hydra_script_b64  = base64encode(file("${path.module}/scripts/create_hydra_client.sh"))
}

################################
# cloud-init
################################
data "cloudinit_config" "ory" {
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.tmpl", {
      # Kratos
      user_email        = var.user_email
      user_name         = var.user_name
      user_role         = var.user_role
      kratos_admin_url  = var.kratos_admin_url

      # Hydra/Grafana
      hydra_admin_url   = var.hydra_admin_url
      hydra_public_url  = var.hydra_public_url
      grafana_domain    = var.grafana_domain
      grafana_client_id = var.grafana_client_id
      grafana_org_role  = var.grafana_org_role

      # scripts (base64)
      kratos_script_b64 = local.kratos_script_b64
      hydra_script_b64  = local.hydra_script_b64
    })
  }
}

################################
# EC2
################################
resource "aws_instance" "ubuntu" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public-01.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id, aws_security_group.allow_grafana_http.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data = data.cloudinit_config.ory.rendered

  ebs_optimized = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = { Name = "ubuntu-ory-grafana" }
}

################################
# Variables
################################
variable "ami_id" {
  description = "AMI ID to use for the instance"
  type        = string
  default     = "ami-04376e1316dedaa10"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m7i.xlarge"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
  default     = "app-deploy-test"
}

# ORY로 보낼 사용자 정보 (Kratos)
variable "user_email" {
  description = "User email to be provisioned into ORY"
  type        = string
  default     = "jbkim@soosan.co.kr"
}

variable "user_name" {
  description = "User name to be provisioned into ORY"
  type        = string
  default     = "jbkim"
}

variable "user_role" {
  description = "User role for Kratos identity"
  type        = string
  default     = "user"
}

# Kratos Admin
variable "kratos_admin_url" {
  description = "Kratos Admin API base URL (without trailing slash)"
  type        = string
  default     = "https://sscr.io/ory/kratos/admin"
}

# Hydra Admin/Public
variable "hydra_admin_url" {
  description = "ORY Hydra Admin API base URL (without trailing slash)"
  type        = string
  default     = "https://sscr.io/ory/hydra/admin"
}

variable "hydra_public_url" {
  description = "ORY Hydra Public base URL (without trailing slash)"
  type        = string
  default     = "https://sscr.io/ory/hydra/public"
}

# Grafana
variable "grafana_domain" {
  description = "Public URL for Grafana (e.g., https://grafana.example.com). If empty, uses http://<public_ip>:3000"
  type        = string
  default     = "https://grafana.example.com"
}

variable "grafana_client_id" {
  description = "OAuth2 client_id to register for Grafana in Hydra"
  type        = string
  default     = "grafana"
}

variable "grafana_org_role" {
  description = "Grafana auto-assign org role for new users (Admin/Editor/Viewer)"
  type        = string
  default     = "Viewer"
}

variable "grafana_ingress_cidrs" {
  description = "CIDRs allowed to reach Grafana (port 3000)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

################################
# Outputs
################################
output "instance_public_ip" {
  value = aws_instance.ubuntu.public_ip
}

output "instance_public_dns" {
  value = aws_instance.ubuntu.public_dns
}

output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.ubuntu.public_ip}"
}

output "kratos_admin_url" {
  value = var.kratos_admin_url
}

output "grafana_url" {
  value = var.grafana_domain != "" ? var.grafana_domain : "http://${aws_instance.ubuntu.public_ip}:3000"
}
