#main Terraform config file
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
  profile = var.aws_profile
}

#generate a key pair for instance SSH access
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#save the private key to a local file
resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/${var.key_name}.pem"
  file_permission = "0600"
}

#create an AWS key pair using the generated public key
resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

#create a file containing Terraform outputs for Ansible to use
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tmpl",
    {
      haproxy_public_ip  = aws_instance.haproxy.public_ip,
      webserver1_private_ip = aws_instance.webserver[0].private_ip,
      webserver2_private_ip = aws_instance.webserver[1].private_ip,
      key_file           = "${path.module}/${var.key_name}.pem"
    }
  )
  filename = "${path.module}/../ansible/inventory/terraform_outputs.yml"
}

#create the Ansible state file that connects Terraform outputs to Ansible variables
resource "local_file" "ansible_state" {
  content = jsonencode({
    "haproxy_public_ip" : aws_instance.haproxy.public_ip,
    "webserver_private_ips" : aws_instance.webserver.*.private_ip,
    "webserver_ids" : aws_instance.webserver.*.id,
    "vpc_id" : aws_vpc.main.id,
    "public_subnet_id" : aws_subnet.public.id,
    "private_subnet_id" : aws_subnet.private.id
  })
  filename = "${path.module}/../ansible/terraform_state.json"
}