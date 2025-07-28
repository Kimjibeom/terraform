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
# Security Groups (최소 SSH만 허용)
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

################################
# cloud-init
################################
data "cloudinit_config" "ory" {
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yaml", {
      user_email       = var.user_email
      user_name        = var.user_name  
      user_role        = var.user_role
      kratos_admin_url = var.kratos_admin_url
    })
  }
}

################################
# EC2
################################
resource "aws_instance" "ubuntu" {
  count                       = 1
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = element([aws_subnet.public-01.id, aws_subnet.public-02.id], count.index)
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data = data.cloudinit_config.ory.rendered

  ebs_optimized = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "ubuntu-instance-${count.index + 1}"
  }
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
}

# ORY로 보낼 사용자 정보
variable "user_email" {
  description = "User email to be provisioned into ORY"
  type        = string
  default     = "user@example.com"
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

# Kratos Admin API Ingress 엔드포인트
variable "kratos_admin_url" {
  description = "Kratos Admin API base URL (without trailing slash)"
  type        = string
  default     = "https://sscr.io/ory/kratos/admin"
}

################################
# Outputs
################################
output "instance_public_ip" {
  value = aws_instance.ubuntu[0].public_ip
}

output "instance_public_dns" {
  value = aws_instance.ubuntu[0].public_dns
}

output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.ubuntu[0].public_ip}"
}

output "kratos_admin_url" {
  value = var.kratos_admin_url
}
