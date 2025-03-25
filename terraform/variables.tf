variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "default"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "key_name" {
  description = "Name of SSH key pair"
  type        = string
  default     = "terraform-ansible-key"
}

variable "haproxy_instance_type" {
  description = "Instance type for HAProxy"
  type        = string
  default     = "t2.micro"
}

variable "webserver_instance_type" {
  description = "Instance type for webservers"
  type        = string
  default     = "t2.micro"
}

variable "webserver_count" {
  description = "Number of webserver instances"
  type        = number
  default     = 2
}

variable "ami_id" {
  description = "AMI ID for Amazon Linux 2"
  type        = string
  default     = "ami-08b5b3a93ed654d19"
}

variable "project_tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Project = "terraform-ansible-aws"
    Owner   = "student"
  }
}