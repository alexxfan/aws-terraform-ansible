#security group for HAProxy
resource "aws_security_group" "haproxy" {
  name        = "haproxy-sg"
  description = "Security group for HAProxy load balancer"
  vpc_id      = aws_vpc.main.id

  #allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  #allow HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  #allow SSH from anywhere (no bastion unfortunately)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }
  #add 9000 for monitoring page
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HAProxy Stats"
  }

  #allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.project_tags,
    {
      Name = "haproxy-sg"
    }
  )
}

#security group for nginx
resource "aws_security_group" "webserver" {
  name        = "webserver-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  #allow HTTP from the HAProxy security group
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.haproxy.id]
    description     = "HTTP from HAProxy"
  }

  #allow SSH from the public subnet
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
    description = "SSH from public subnet"
  }

  #allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.project_tags,
    {
      Name = "webserver-sg"
    }
  )
}