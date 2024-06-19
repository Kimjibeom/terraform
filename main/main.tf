provider "aws" {
    region = "us-east-2"
}

resource "aws_instance" "terraform" {
    ami = "ami-0c55b159cbfafe1f0"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.instance.id]

    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, World" > index.html
                nohup busybox httpd -f -p 8080 &
                EOF
 
    tags = {
        Name = "terraform"
    }
}

resource "aws_security_group" "instance" {
    name = "terraform-instance"

    ingress {
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

variable "number_example" {
    description = "An example of a njumber variable in Terraform"
    type = number
    default = 42
}

variable "list_example" {
    description = "An example of a list in Terraform"
    type = list
    default = ["a", "b", "c"]
}

variable "list_numeric_example" {
    description = "An example of a numeric list in Terraform"
    type = list(number)
    default = [1, 2, 3]
}

variable "map_example" {
    description = "An example of a map in Terraform"
    type = map(string)

    default = {
        key1 = "value1"
        key2 = "value2"
        key3 = "value3"
    }
}

variable "object_example" {
    description = "An example of a structural type in Terraform"
    type = object({
        name    = string
        age     = number
        tags    = list(string)
        enabled = bool
    })
    default = {
        name    = "value1"
        age     = 42
        tags    = ["a", "b", "c"]
        enabled = true
    }
}