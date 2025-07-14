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

# EC2 인스턴스를 public 서브넷에 배포
resource "aws_instance" "ubuntu" {
  count                       = 1
  ami                         = "ami-08943a151bd468f4e"
  instance_type               = "t3.nano"
  subnet_id                   = element([aws_subnet.public-01.id, aws_subnet.public-02.id], count.index)
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true
  key_name                    = "iac"

  tags = {
    Name = "ubuntu-instance-${count.index + 1}"
  }
}


