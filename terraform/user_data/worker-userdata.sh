#!/bin/bash
set -e

# Worker Server User Data Script
echo "Starting Worker Server initialization..."

# Update system packages
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    curl \
    wget

echo "Installed system packages"

# Create application directory
APP_DIR="/opt/karate-worker"
mkdir -p $APP_DIR
cd $APP_DIR

# Clone application code from Git or download from S3
# Modify this section based on your deployment strategy
if [ -n "${GIT_REPO_URL}" ] && [ "${GIT_REPO_URL}" != "" ]; then
    echo "Cloning from Git repository: ${GIT_REPO_URL}"
    git clone ${GIT_REPO_URL} .
else
    echo "Git repository not provided. Deploying from local source..."
    # Placeholder for S3 download or other deployment method
    # aws s3 cp s3://your-bucket/karate-worker.tar.gz . && tar -xzf karate-worker.tar.gz
fi

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install Python dependencies
pip install -r worker/requirements.txt

echo "Installed Python dependencies"

# Create environment file for the service
cat > /opt/karate-worker/.env << EOF
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
RABBITMQ_HOST=${RABBITMQ_HOST}
RABBITMQ_PORT=${RABBITMQ_PORT}
EOF

echo "Created environment configuration"

# Create systemd service for the Worker
cat > /etc/systemd/system/karate-worker.service << EOF
[Unit]
Description=Karate Combats Worker Service
After=network.target
Requires=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/karate-worker
EnvironmentFile=/opt/karate-worker/.env
ExecStart=/opt/karate-worker/venv/bin/python worker/worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Fix permissions
chown -R ubuntu:ubuntu /opt/karate-worker

echo "Created systemd service"

# Enable and start the service
systemctl daemon-reload
systemctl enable karate-worker.service

# Wait for RabbitMQ and PostgreSQL to be ready before starting worker
echo "Waiting for backend services to be ready..."

# Function to check if a service is available
check_service() {
    local host=$1
    local port=$2
    local name=$3
    
    for i in {1..60}; do
        if timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            echo "✓ $name is ready"
            return 0
        fi
        echo "  Waiting for $name... ($i/60)"
        sleep 2
    done
    
    echo "✗ $name did not respond in time"
    return 1
}

# Check RabbitMQ
check_service "${RABBITMQ_HOST}" "${RABBITMQ_PORT}" "RabbitMQ" || true

# Check PostgreSQL
check_service "${DB_HOST}" "${DB_PORT}" "PostgreSQL" || true

# Give a bit more time for full initialization
echo "Giving services additional time to stabilize..."
sleep 10

# Start the worker service
systemctl start karate-worker.service

echo "Started karate-worker service"

# Wait for service to establish connection
sleep 5

# Check if service is running
if systemctl is-active --quiet karate-worker; then
    echo "✓ Worker Service is running successfully"
    echo "Logs: journalctl -u karate-worker -f"
else
    echo "✗ Worker Service failed to start"
    echo "Checking logs..."
    journalctl -u karate-worker -n 50 || true
fi

echo "Worker Server initialization complete!"
