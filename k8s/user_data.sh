#!/bin/sh -x

# INSTALL DOCKER
sudo apt update -y
sudo apt -y install docker.io
sudo service docker start
sudo usermod -a -G docker ubuntu
sudo chmod 666 /var/run/docker.sock
docker version

# INSTALL NVM
export HOME=/home/ubuntu
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# INSTALL NODE 20.16.0
nvm install 20.16.0
nvm use 20.16.0

# INSTALL DEVCONTAINERS CLI 0.65.0
npm install -g @devcontainers/cli@0.65.0

# INSTALL MAKE AND SETUP DEV CONTAINER
sudo apt install make
cd $HOME
git clone https://github.com/Digital-Defiance/cloud-infrastructure.git
cd cloud-infrastructure
make build
