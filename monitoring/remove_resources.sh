#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m'

check_stage() {
  sleep 1
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error occurred in stage: $1. > Exiting.${NC}"
    exit 1
  else
    echo -e "${GREEN}Stage \"$1\" executed successfully.${NC}"
  fi
}

check_and_remove() {
  local file="$1"
  if [ -f "$file" ]; then
    echo "Removing file: $file"
    sudo rm -f $file
  fi
}

check_and_rmdir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    echo "Removing directory: $dir"
    sudo rm -rf $dir
  fi
}

check_and_userdel() {
  local user="$1"
  if id -u "$user" >/dev/null 2>&1; then
    echo "Deleting user: $user"
    sudo killall -u $user
    sudo deluser -f $user
  fi
}

uninstall_grafana_if_exists() {
  # Check if Grafana package is installed
  if dpkg -l grafana >/dev/null 2>&1; then
    echo "Grafana is installed. Uninstalling..."
    sudo apt remove grafana -y
    sudo rm -rf /etc/grafana
    check_stage "Uninstall Grafana"
  else
    echo "Grafana is not installed. Skipping uninstallation."
  fi
}

# Stage 1: Remove Prometheus and Node Exporter from /usr/local/bin (if exist)
STAGE="Removing Prometheus and Node Exporter files (if exist)"
echo -e "${BLUE}Stage 1: $STAGE${NC}"

check_and_remove /usr/local/bin/node_exporter
check_and_remove /usr/local/bin/prometheus

# Stage 2: Uninstall Grafana using apt
STAGE="Uninstalling Grafana"
echo -e "${BLUE}Stage 2: $STAGE${NC}"

uninstall_grafana_if_exists

# Stage 3: Delete systemd services (if exist) remaining from previous installation (optional)
STAGE="Deleting systemd services (if exist)"
echo -e "${BLUE}Stage 3: $STAGE${NC}"


check_and_remove /etc/systemd/system/node_exporter.service
check_and_remove /etc/systemd/system/prometheus.service
check_and_remove /etc/systemd/system/grafana-server.service

sudo systemctl daemon-reload

# Stage 4: Delete Users (if exist) remaining from previous installation (optional)
STAGE="Deleting users (if exist)"
echo -e "${BLUE}Stage 4: $STAGE${NC}"
check_and_userdel node_exporter
check_and_userdel prometheus

# Stage 5: Delete Directories and Files (if exist) remaining from previous installation (optional)
STAGE="Deleting directories and files (if exist)"
echo -e "${BLUE}Stage 5: $STAGE${NC}"

check_and_rmdir /var/lib/prometheus
check_and_rmdir /etc/prometheus
check_and_rmdir /etc/node_exporter
sudo rm -rf /tmp/prom*
sudo rm -rf /tmp/node_*

echo -e "${GREEN}Uninstall complete.${NC}"
