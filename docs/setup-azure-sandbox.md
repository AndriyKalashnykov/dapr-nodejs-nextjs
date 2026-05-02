# Azure Sandbox Setup Guide

This guide walks you through setting up a development environment for use as a sandbox in Azure. The setup includes installing necessary packages, configuring Podman, and preparing the environment for development.

## Azure Requirements

- **Nested Virtualization**: The Azure VM **must support nested virtualization**. This is required for running Podman and Docker containers within the VM. The `Standard_D2s_v3` (2vCPU/8gb RAM) or `Standard_D4s_v3` (4vCPU/16gb RAM) is a good choice for this purpose.

## Linux OS Requirements

- **Podman 5.x**: Podman is a container management tool that allows you to run and manage containers without requiring a daemon.
- **Docker Compose 2.x**: Docker Compose is a tool for defining and running multi-container Docker applications, it is used by podman when using `podman compse` commands.
- **Disk Space**: Ideally the sandbox VM should have at least 50GB of disk space available, this will help prevent issues with running out of disk space when building images and running containers.

### Linux Distributions supporting Podman 5.x

- **Ubuntu 25+**
- **Fedora 40+**
- **Red Hat Enterprise Linux 9.5+**

# Setup Ubuntu 25.04 VM in Azure

## 🖥️ Create Ubuntu 25 VM using Canonical Ubuntu 25.04 from the Marketplace

See the marketplace link for the latest version of Ubuntu 25.04.
[Canonical Ubuntu 25.04 Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/canonical.ubuntu-25_04)

---

## 📦 System Package Installation

Update package lists and install required tools:

```bash
sudo apt update
sudo apt install podman vim qemu-system-x86 unzip gvproxy virtiofsd git make jq
```

---

## 🔧 User & Podman Configuration

Add your user to the `kvm` group and fix Podman's required symlinks:

```bash
sudo usermod -aG kvm azureuser

# Create symlinks for Podman support files
sudo ln -s /usr/libexec/virtiofsd /usr/libexec/podman/virtiofsd
sudo ln -s /usr/bin/gvproxy /usr/libexec/podman/gvproxy
```

---

## 🐳 Docker Compose Setup

Download and install Docker Compose v2 executable:

```bash
sudo curl -SL https://github.com/docker/compose/releases/download/v2.36.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

---

## 🔌 Enable Podman API Socket

```bash
systemctl --user enable --now podman.socket
```

---

## 🚀 Install Node Version Manager (FNM)

```bash
curl -fsSL https://fnm.vercel.app/install | bash
```

---

## 🖥️ Logout and log back in to ensure your user has access to the `kvm` group.

Start a new terminal session to ensure that the `azureuser` has access to the `kvm` group and the `fnm` command is available.

---

## 🤖️ Set Up Podman Machine

```bash
podman machine init
podman machine start
```

---

## 📦 Install Node.js (v22)

```bash
fnm install 22
```

---

## 🧪 Setup Demo Project

Clone the project into the `azureuser` home directory:

```bash
git clone https://github.com/AndriyKalashnykov/dapr-nodejs-nextjs.git ~/dapr-nodejs-nextjs
cd ~/dapr-nodejs-nextjs
```

Install dependencies and build:

```bash
make install        # Install pnpm packages
make setup          # Build base Docker images (first time only)
make build          # Build service containers
make up             # Start the full stack
```

---

## 🖥️ Open another terminal session while the project is running

Example uses for this terminal session:

- Run `curl` commands to test the API
- Edit `~/dapr-nodejs-nextjs/app/backend-ts/src/*` files for live reloading and development

---

# Example curl commands

```bash
# Get all todos
curl -H 'dapr-app-id:backend-ts' \
     -H 'authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhMWIyYzMiLCJuYW1lIjoiSm9obiBEb2UiLCJpYXQiOjE1MTYyMzkwMjJ9.G5wdYS1G5gfd14BnsXrZ0JcLW0kB5ItFd7M_9elzjUQ' \
http://localhost:3500/api/v1/todos | jq

# Create a new todo
curl -X POST \
     -H 'dapr-app-id:backend-ts' \
     -H 'authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhMWIyYzMiLCJuYW1lIjoiSm9obiBEb2UiLCJpYXQiOjE1MTYyMzkwMjJ9.G5wdYS1G5gfd14BnsXrZ0JcLW0kB5ItFd7M_9elzjUQ' \
     -H 'Content-Type: application/json' \
     -d '{"title":"New Todo"}' \
http://localhost:3500/api/v1/todos | jq

# Get a todo
curl -H 'dapr-app-id:backend-ts' \
     -H 'authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhMWIyYzMiLCJuYW1lIjoiSm9obiBEb2UiLCJpYXQiOjE1MTYyMzkwMjJ9.G5wdYS1G5gfd14BnsXrZ0JcLW0kB5ItFd7M_9elzjUQ' \
http://localhost:3500/api/v1/todos/e1532a16-e1cf-481e-b98c-0f7fbfceb942 | jq

# Update a todo
curl -X PUT \
     -H 'dapr-app-id:backend-ts' \
     -H 'authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhMWIyYzMiLCJuYW1lIjoiSm9obiBEb2UiLCJpYXQiOjE1MTYyMzkwMjJ9.G5wdYS1G5gfd14BnsXrZ0JcLW0kB5ItFd7M_9elzjUQ' \
     -H 'Content-Type: application/json' \
     -d '{"title":"Updated title for todo"}' \
http://localhost:3500/api/v1/todos/e1532a16-e1cf-481e-b98c-0f7fbfceb942 | jq

# Delete a todo
curl -X DELETE \
     -H 'dapr-app-id:backend-ts' \
     -H 'authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhMWIyYzMiLCJuYW1lIjoiSm9obiBEb2UiLCJpYXQiOjE1MTYyMzkwMjJ9.G5wdYS1G5gfd14BnsXrZ0JcLW0kB5ItFd7M_9elzjUQ' \
http://localhost:3500/api/v1/todos/e1532a16-e1cf-481e-b98c-0f7fbfceb942 | jq

```
