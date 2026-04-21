#!/bin/bash
set -e

# API Server User Data Script
echo "Starting API Server initialization..."

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
    wget \
    nginx

echo "Installed system packages"

# Create application directory
APP_DIR="/opt/karate-api"
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
    # aws s3 cp s3://your-bucket/karate-api.tar.gz . && tar -xzf karate-api.tar.gz
fi

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install Python dependencies
pip install -r api/requirements.txt

echo "Installed Python dependencies"

# Create environment file for the service
cat > /opt/karate-api/.env << EOF
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
RABBITMQ_HOST=${RABBITMQ_HOST}
RABBITMQ_PORT=${RABBITMQ_PORT}
FLASK_ENV=production
FLASK_DEBUG=0
EOF

echo "Created environment configuration"

# Create systemd service for the API
cat > /etc/systemd/system/karate-api.service << EOF
[Unit]
Description=Karate Combats API Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/karate-api
EnvironmentFile=/opt/karate-api/.env
ExecStart=/opt/karate-api/venv/bin/python -m flask --app api.app run --host=0.0.0.0 --port=5000
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
EOF

# Fix permissions
chown -R ubuntu:ubuntu /opt/karate-api

echo "Created systemd service"

# Enable and start the service
systemctl daemon-reload
systemctl enable karate-api.service
systemctl start karate-api.service

echo "Started karate-api service"

# Configure nginx as reverse proxy
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /swagger/ {
        proxy_pass http://127.0.0.1:5000/apidocs/;
    }
}
EOF

# Test nginx configuration
nginx -t

# Restart nginx
systemctl restart nginx

echo "Configured nginx as reverse proxy"

# Wait for service to be ready
sleep 5

# Check if service is running
if systemctl is-active --quiet karate-api; then
    echo "✓ API Server is running successfully"
else
    echo "✗ API Server failed to start"
    systemctl status karate-api
fi

echo "API Server initialization complete!"
