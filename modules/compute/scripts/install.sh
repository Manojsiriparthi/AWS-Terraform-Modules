#!/bin/bash
# ==============================================================================
# USER DATA SCRIPT — runs as root on first boot of the EC2 instance
# Installs: system updates, Jenkins, Docker, Terraform
# Ubuntu 22.04 (Jammy)
# ==============================================================================

set -euo pipefail   # exit on error, undefined var, or pipe failure
exec > /var/log/user-data.log 2>&1  # log all output for debugging

echo "========================================="
echo " Starting bootstrap: $(date)"
echo "========================================="

# ------------------------------------------------------------------------------
# 1. SYSTEM UPDATE
# Always update before installing packages — security patches matter.
# ------------------------------------------------------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates unzip

# ------------------------------------------------------------------------------
# 2. INSTALL DOCKER
# Docker lets us run containerised applications without VM overhead.
# ------------------------------------------------------------------------------
echo "--- Installing Docker ---"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable Docker to start on boot and start it now
systemctl enable docker
systemctl start docker

# Add the default ubuntu user to the docker group so they can run docker without sudo
usermod -aG docker ubuntu

echo "Docker version: $(docker --version)"

# ------------------------------------------------------------------------------
# 3. INSTALL JENKINS
# Jenkins is the most widely used open-source CI/CD server.
# ------------------------------------------------------------------------------
echo "--- Installing Jenkins ---"
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

# Jenkins requires Java 17
apt-get update -y
apt-get install -y openjdk-17-jdk jenkins

systemctl enable jenkins
systemctl start jenkins

echo "Jenkins installed. Access on port 8080 after security group allows it."
echo "Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'not ready yet')"

# ------------------------------------------------------------------------------
# 4. INSTALL TERRAFORM
# We install the latest stable release from HashiCorp's official repo.
# ------------------------------------------------------------------------------
echo "--- Installing Terraform ---"
wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list

apt-get update -y
apt-get install -y terraform

echo "Terraform version: $(terraform version)"

# ------------------------------------------------------------------------------
# 5. INSTALL AWS CLI v2
# Needed for scripts that interact with AWS services directly.
# ------------------------------------------------------------------------------
echo "--- Installing AWS CLI v2 ---"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

echo "AWS CLI version: $(aws --version)"

# ------------------------------------------------------------------------------
# 6. INSTALL KUBECTL  (for managing the EKS cluster from this server)
# ------------------------------------------------------------------------------
echo "--- Installing kubectl ---"
KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
curl -fsSLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

echo "kubectl version: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

echo "========================================="
echo " Bootstrap complete: $(date)"
echo "========================================="
