provider "aws" {
    region = "ap-northeast-2"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-gw"
  }
}

# 서브넷 생성 (public)
resource "aws_subnet" "public-01" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/20"

  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet-01"
  }
}

resource "aws_subnet" "public-02" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.16.0/20"

  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet-02"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

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

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id
  name = "web"
  description = "web"

  # 인바운드 규칙 설정
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "http"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "https"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Keycloak 포트 추가
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    description = "keycloak"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL 포트 추가
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    description = "postgresql"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드 규칙 설정
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 라우팅 테이블과 서브넷 관계 설정
resource "aws_route_table_association" "public-01" {
  subnet_id      = aws_subnet.public-01.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public-02" {
  subnet_id      = aws_subnet.public-02.id
  route_table_id = aws_route_table.public.id
}

data "cloudinit_config" "keycloak" {
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/cloud-init.yaml", {
      user_id  = var.user_id
      user_email = var.user_email
    })
  }
}

# EC2 인스턴스를 public 서브넷에 배포
resource "aws_instance" "ubuntu" {
  count                       = 1
  ami                         = var.ami_id
  instance_type               = var.instance_type 
  subnet_id                   = element([aws_subnet.public-01.id, aws_subnet.public-02.id], count.index)
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id, aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data = data.cloudinit_config.keycloak.rendered

  # EBS 최적화 활성화 (성능 향상)
  ebs_optimized = true

  # 루트 볼륨 설정
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "ubuntu-instance-${count.index + 1}"
  }
}

# 변수 정의
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

variable "user_id" {
  description = "User ID for the web application"
  type        = string
  default     = "webappuser"
}

variable "user_email" {
  description = "User email for the web application"
  type        = string
  default     = "user@example.com"
}


# 퍼블릭 IP 출력
output "instance_public_ip" {
  value = aws_instance.ubuntu[0].public_ip
}

output "instance_public_dns" {
  value = aws_instance.ubuntu[0].public_dns
}

# 접속 정보 출력
output "ssh_command" {
  value = "ssh -i app-deploy-test.pem ubuntu@${aws_instance.ubuntu[0].public_ip}"
}

output "keycloak_url" {
  value = "http://${aws_instance.ubuntu[0].public_ip}:8080/admin/"
}