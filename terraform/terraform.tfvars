aws_region = "us-east-1"
aws_profile = "default"
vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
key_name = "terraform-ansible-key"
haproxy_instance_type = "t2.micro"
webserver_instance_type = "t2.micro"
webserver_count = 2
ami_id = "ami-08b5b3a93ed654d19"
project_tags = {
  Project = "terraform-ansible-aws"
  Owner   = "student"
}