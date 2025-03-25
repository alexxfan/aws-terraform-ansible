output "haproxy_public_ip" {
  description = "Public IP address of the HAProxy instance"
  value       = aws_instance.haproxy.public_ip
}

output "haproxy_public_dns" {
  description = "Public DNS of the HAProxy instance"
  value       = aws_instance.haproxy.public_dns
}

output "webserver_private_ips" {
  description = "Private IP addresses of the webserver instances"
  value       = aws_instance.webserver.*.private_ip
}

output "webserver_ids" {
  description = "IDs of the webserver instances"
  value       = aws_instance.webserver.*.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "ssh_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_file.private_key.filename
}