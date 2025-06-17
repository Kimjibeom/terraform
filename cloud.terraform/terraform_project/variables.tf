variable "region" {
  type        = string
  description = "AWS region to deploy resources"
}

variable "ami" {
  type        = string
  description = "AMI ID to use for EC2 instances"
}

variable "instance_type" {
  type        = string
  description = "Instance type for EC2"
}

variable "key_name" {
  type        = string
  description = "EC2 SSH key pair name"
}
