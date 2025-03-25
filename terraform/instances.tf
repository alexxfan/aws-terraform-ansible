#create HAProxy instance in the public subnet
resource "aws_instance" "haproxy" {
  ami                    = var.ami_id
  instance_type          = var.haproxy_instance_type
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.haproxy.id]
  subnet_id              = aws_subnet.public.id
  
  # User data to install Python for Ansible
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3
              EOF

  tags = merge(
    var.project_tags,
    {
      Name = "haproxy-lb"
      Role = "haproxy"
    }
  )
}

#create nginx instances in the private subnet
resource "aws_instance" "webserver" {
  count                  = var.webserver_count
  ami                    = var.ami_id
  instance_type          = var.webserver_instance_type
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.webserver.id]
  subnet_id              = aws_subnet.private.id
  
  # User data to install Python for Ansible
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3
              EOF

  tags = merge(
    var.project_tags,
    {
      Name = "webserver-${count.index + 1}"
      Role = "webserver"
    }
  )
}