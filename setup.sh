#!/bin/bash

#terraform and ansible AWS provision script
set -e

echo "==== Starting Infrastructure Deployment ===="

VENV_DIR="./venv"


#use venv
if [ ! -d "$VENV_DIR" ] || [ ! -f "$VENV_DIR/bin/activate" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv $VENV_DIR
  source $VENV_DIR/bin/activate
  pip install boto3 ansible
else
  echo "Using existing virtual environment..."
  source $VENV_DIR/bin/activate
fi


#check aws cli and terraform exists
echo "Checking prerequisites..."
for cmd in aws terraform; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed. Please install it and try again."
    exit 1
  fi
done

#check aws cli is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Error: AWS CLI is not configured. Please run 'aws configure' first."
  exit 1
fi

#use terraform
echo "==== Setting up Terraform infrastructure ===="
cd terraform

#add port 9000 to security group
echo "Ensuring security group allows HAProxy stats..."
if ! grep -q "HAProxy Stats" security.tf; then
  echo "Adding port 9000 to security group..."
  sed -i.bak '/description      = "SSH"/,/},/ {
    /},/ s/},/},\n\n  # Allow HAProxy stats page\n  ingress {\n    from_port   = 9000\n    to_port     = 9000\n    protocol    = "tcp"\n    cidr_blocks = ["0.0.0.0\/0"]\n    description = "HAProxy Stats"\n  },/
  }' security.tf
fi

#check for the aws_eip issue and fix it
if grep -q "domain = \"vpc\"" networking.tf; then
  echo "Fixing aws_eip configuration in networking.tf..."
  sed -i.bak 's/domain = "vpc"/vpc = true/g' networking.tf
  echo "Fixed aws_eip configuration."
fi

#init terraform
echo "Initializing Terraform..."
terraform init

#apply terraform
echo "Applying Terraform configuration..."
terraform apply -auto-approve

#create json file of terraform outputs for ansible to read
echo "Creating terraform state file for Ansible..."
mkdir -p ../ansible/inventory
terraform output -json > ../ansible/terraform_state.json
HAPROXY_IP=$(terraform output -raw haproxy_public_ip)
WEBSERVER1_IP=$(terraform output -json webserver_private_ips | jq -r '.[0]')
WEBSERVER2_IP=$(terraform output -json webserver_private_ips | jq -r '.[1]')

#setup ansible
echo "==== Setting up Ansible configuration ===="
cd ../ansible

# # Create vault password if it doesn't exist
# if [ ! -f ".vault_pass.txt" ]; then
#   echo "Creating Ansible Vault password file..."
#   echo "secure-password" > .vault_pass.txt
#   chmod 600 .vault_pass.txt
# fi

#create SSH config to disable host key checking
mkdir -p ~/.ssh
cat > ~/.ssh/config << EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
chmod 600 ~/.ssh/config

#create or update ansible.cfg with proxy configuration
echo "Updating Ansible configuration..."
cat > ansible.cfg << EOF
[defaults]
inventory = inventory/
host_key_checking = False
remote_user = ec2-user
private_key_file = ../terraform/terraform-ansible-key.pem
roles_path = roles
timeout = 60
interpreter_python = /usr/bin/python3
vault_password_file = .vault_pass.txt

[ssh_connection]
pipelining = True
ssh_args = -o ProxyCommand="ssh -i ../terraform/terraform-ansible-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ec2-user@${HAPROXY_IP}"
EOF

#update inventory files with correct IPs
echo "Updating inventory files with current IPs..."
mkdir -p inventory

#create/update webservers.ini
cat > inventory/webservers.ini << EOF
[webservers]
webserver1 ansible_host=${WEBSERVER1_IP}
webserver2 ansible_host=${WEBSERVER2_IP}
EOF

#create/update haproxy.ini
cat > inventory/haproxy.ini << EOF
[haproxy]
haproxy_server ansible_host=${HAPROXY_IP}
EOF

#update playbooks to match inventory hosts
echo "Updating playbook host patterns..."
if [ -f "playbooks/haproxy.yml" ]; then
  sed -i.bak 's/hosts: tag_role_haproxy/hosts: haproxy/g' playbooks/haproxy.yml
  sed -i.bak 's/hosts: tag_role_webserver/hosts: webservers/g' playbooks/webservers.yml
fi

#create group_vars if they don't exist
echo "Ensuring group variables exist..."
mkdir -p group_vars

#create all.yml if it doesn't exist
if [ ! -f "group_vars/all.yml" ]; then
  cat > group_vars/all.yml << EOF
---
# Common variables for all servers
ansible_user: ec2-user
ansible_ssh_private_key_file: "{{ lookup('env', 'PWD') }}/../terraform/terraform-ansible-key.pem"
ansible_python_interpreter: /usr/bin/python3

# Common packages to install on all servers
common_packages:
  - vim
  - htop
  - wget
  - tree
  - git

# Firewall configuration
firewall_enabled: true
EOF
fi

#create haproxy.yml if it doesn't exist
if [ ! -f "group_vars/haproxy.yml" ]; then
  cat > group_vars/haproxy.yml << EOF
---
# HAProxy configuration variables
haproxy_global_options:
  - "log /dev/log local0"
  - "log /dev/log local1 notice"
  - "chroot /var/lib/haproxy"
  - "stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners"
  - "stats timeout 30s"
  - "user haproxy"
  - "group haproxy"
  - "daemon"

haproxy_defaults_options:
  - "log global"
  - "mode http"
  - "option httplog"
  - "option dontlognull"
  - "timeout connect 5000"
  - "timeout client 50000"
  - "timeout server 50000"

# HAProxy frontend configuration
haproxy_frontend_name: "http-in"
haproxy_frontend_bind_address: "*"
haproxy_frontend_bind_port: "80"
haproxy_frontend_options:
  - "default_backend web-backend"

# HAProxy backend configuration
haproxy_backend_name: "web-backend"
haproxy_backend_options:
  - "balance roundrobin"

# Web servers to load balance
haproxy_backend_servers:
  - "${WEBSERVER1_IP}"
  - "${WEBSERVER2_IP}"

# HAProxy stats
haproxy_stats_enabled: true
haproxy_stats_uri: /haproxy-stats
haproxy_stats_user: admin
haproxy_stats_password: password123
EOF
fi

#create webservers.yml if it doesn't exist
if [ ! -f "group_vars/webservers.yml" ]; then
  cat > group_vars/webservers.yml << EOF
---
# Nginx configuration variables
nginx_port: 80
nginx_server_name: "_"  # Catch-all server name
nginx_root: /var/www/html
nginx_index: index.html
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_server_tokens: "off"  # Hide nginx version

# Sample webpage content
website_content: |
  <!DOCTYPE html>
  <html>
  <head>
    <title>Terraform & Ansible AWS Demo</title>
    <style>
      body {
        width: 80%;
        margin: 0 auto;
        font-family: Arial, sans-serif;
        text-align: center;
        padding-top: 50px;
      }
      h1 {
        color: #333;
      }
      .server-info {
        background-color: #f4f4f4;
        border-radius: 5px;
        padding: 20px;
        margin-top: 20px;
      }
    </style>
  </head>
  <body>
    <h1>Welcome to Terraform & Ansible AWS Demo</h1>
    <div class="server-info">
      <h2>Server Information</h2>
      <p>Server: {{ ansible_hostname }}</p>
      <p>IP Address: {{ ansible_default_ipv4.address }}</p>
      <p>Operating System: {{ ansible_distribution }} {{ ansible_distribution_version }}</p>
      <p>Current Time: {{ ansible_date_time.iso8601 }}</p>
    </div>
  </body>
  </html>
EOF
fi

#update HAProxy template with correct webserver IPs
echo "Updating HAProxy configuration template..."
mkdir -p roles/haproxy/templates
if [ -f "roles/haproxy/templates/haproxy.cfg.j2" ]; then
  # Update server entries in existing template
  sed -i.bak -E "s/server webserver1 [0-9.]*:80/server webserver1 ${WEBSERVER1_IP}:80/" roles/haproxy/templates/haproxy.cfg.j2
  sed -i.bak -E "s/server webserver2 [0-9.]*:80/server webserver2 ${WEBSERVER2_IP}:80/" roles/haproxy/templates/haproxy.cfg.j2
else
  # Create new template
  cat > roles/haproxy/templates/haproxy.cfg.j2 << EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend {{ haproxy_frontend_name }}
    bind {{ haproxy_frontend_bind_address }}:{{ haproxy_frontend_bind_port }}
{% for option in haproxy_frontend_options %}
    {{ option }}
{% endfor %}

backend {{ haproxy_backend_name }}
    balance roundrobin
    server webserver1 ${WEBSERVER1_IP}:80 check
    server webserver2 ${WEBSERVER2_IP}:80 check

{% if haproxy_stats_enabled %}
listen stats
    bind *:9000
    stats enable
    stats uri {{ haproxy_stats_uri }}
    stats realm Haproxy\ Statistics
    stats auth {{ haproxy_stats_user }}:{{ haproxy_stats_password }}
    stats refresh 10s
{% endif %}
EOF
fi

#create HAProxy vars file if it doesn't exist
echo "Ensuring HAProxy role vars file exists..."
mkdir -p roles/haproxy/vars
if [ ! -f "roles/haproxy/vars/main.yml" ]; then
  cat > roles/haproxy/vars/main.yml << EOF
---
# HAProxy role variables
haproxy_stats_enabled: true
haproxy_stats_uri: /haproxy-stats
haproxy_stats_user: admin
haproxy_stats_password: password123
EOF
fi

#wait for instances to be ready
echo "Waiting for instances to be ready (this may take a minute)..."
# sleep 60

#test SSH connection to HAProxy
echo "Testing SSH connection to HAProxy..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ../terraform/terraform-ansible-key.pem ec2-user@$HAPROXY_IP "echo SSH to HAProxy successful"

#run ansible
echo "==== Running Ansible playbooks ===="

#create/update haproxy.ini to ensure haproxy_server is in the haproxy group
cat > inventory/haproxy.ini << EOF
[haproxy]
haproxy_server ansible_host=${HAPROXY_IP}
EOF

#add before running the playbooks
echo "Ensuring SSH connectivity to HAProxy..."
for i in {1..5}; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ../terraform/terraform-ansible-key.pem ec2-user@$HAPROXY_IP "exit"; then
    echo "SSH connection to HAProxy successful"
    break
  fi
  echo "Retrying SSH connection to HAProxy (attempt $i of 5)..."
  sleep 10
done

#and when running ansible-playbook, explicitly include the variables
echo "Configuring HAProxy..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/haproxy.yml -i inventory/haproxy.ini -e @group_vars/haproxy.yml -vv

echo "Configuring webservers..."

#add firewall configuration for HAProxy stats, also configure nginx servers
echo "Configuring webservers..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/webservers.yml -i inventory/webservers.ini -e @group_vars/webservers.yml -vv

echo "======================================================"
echo "Setup Complete!"
echo "HAProxy is accessible at: http://${HAPROXY_IP}"
echo "HAProxy Stats page: http://${HAPROXY_IP}:9000/haproxy-stats"
echo "  Username: admin"
echo "  Password: password123"
echo "======================================================"

echo "To destroy the infrastructure when you're done, run:"
echo "cd terraform && terraform destroy -auto-approve"

#deactivate venv
deactivate