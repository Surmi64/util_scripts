#!/bin/bash

sudo ./remove_resources.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m'

# Versions
NODE_EXPORTER_VERSION="1.8.1"
PROMETHEUS_VERSION="2.45.5"

check_stage() {
  sleep 2
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error occurred in stage: $1. > Exiting.${NC}"
    exit 1
  else
    echo -e "${GREEN}Stage \"$1\" executed successfully.${NC}"
  fi
}

check_step() {
  sleep 2
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error occurred in step: $1. > Exiting.${NC}"
    exit 1
  else
    echo -e "${GREEN}Step \"$1\" executed successfully.${NC}"
  fi
}

# Stage 1: Update and install dependencies
STAGE="Updating system and installing dependencies"
echo -e "${BLUE}Stage 1: $STAGE${NC}"
sudo apt update && sudo apt upgrade -y
check_step "Update and upgrade system"

sudo apt install -y wget curl gnupg2 software-properties-common
check_stage "$STAGE"

# Stage 2: Install and configure Node Exporter
STAGE="Installing Node Exporter"
echo -e "${BLUE}Stage 2: $STAGE${NC}"
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
check_step "Download Node Exporter"

tar -xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
check_step "Extract Node Exporter"

sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
check_step "Move Node Exporter to /usr/local/bin"

sudo useradd -rs /bin/false node_exporter
check_step "Create Node Exporter user"

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
User=node_exporter
Group=node_exporter
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/node_exporter \
    --collector.logind

[Install]
WantedBy=multi-user.target
EOF
check_step "Create systemd service for Node Exporter"

sudo systemctl daemon-reload
check_step "Reload systemd daemon"

sudo systemctl start node_exporter
check_step "Start Node Exporter service"

sudo systemctl enable node_exporter
check_stage "$STAGE"

# Stage 3: Install and configure Prometheus
STAGE="Installing Prometheus"
echo -e "${BLUE}Stage 3: $STAGE${NC}"

cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
check_step "Download Prometheus"

tar -xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
check_step "Extract Prometheus"

sudo mkdir /etc/prometheus
sudo mkdir /var/lib/prometheus
check_step "Create Prometheus directories"

sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
check_step "Move Prometheus binaries to /usr/local/bin"

sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus/
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus/
check_step "Move Prometheus consoles and libraries"

sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus.yml /etc/prometheus/prometheus.yml
check_step "Move Prometheus configuration file"

# Create Prometheus user with specified options
sudo useradd \
  --system \
  --no-create-home \
  --shell /bin/false \
  prometheus
check_step "Create Prometheus user"

sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
check_step "Set ownership of Prometheus directories"

sudo tee /etc/prometheus/web.yml > /dev/null <<EOF
basic_auth_users:
    admin: \$2a\$12\$xl03KLxfae7UCTsrpb/mUOcHTKM.kkMB/HJQXGoUWIYPY9kJqcHC.
EOF
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yml \
  --storage.tsdb.path /var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle \
  --web.config.file=/etc/prometheus/web.yml

[Install]
WantedBy=multi-user.target
EOF
check_step "Create systemd service for Prometheus"

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
# my global config
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "node_exp"
    static_configs:
      - targets: ["localhost:9100"]
EOF
check_step "Connect node_exporter to Prometheus"

sudo promtool check config /etc/prometheus/prometheus.yml
check_step "Validate prometheus.yml"

sudo systemctl daemon-reload
check_step "Reload systemd daemon"

sudo systemctl start prometheus
check_step "Start Prometheus service"

sudo systemctl enable prometheus
check_stage "$STAGE"

# Stage 4: Install and configure Grafana
STAGE="Installing Grafana"
echo -e "${BLUE}Stage 4: $STAGE${NC}"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
check_step "Add Grafana GPG key"

sudo apt-get install -y apt-transport-https software-properties-common
check_step "Check and install Grafana dependecies"

if ! grep -q "grafana" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
fi
check_step "Add Grafana repository"

sudo apt update
sudo apt install -y grafana
check_step "Install Grafana"

sudo systemctl start grafana-server
check_step "Start Grafana service"

sudo systemctl enable grafana-server
check_stage "$STAGE"

echo -e "${GREEN}Installation complete. All services were created."
echo -e "Checking service statuses:"
sudo systemctl status prometheus node_exporter grafana-server
