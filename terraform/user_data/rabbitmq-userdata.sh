#!/bin/bash
set -e

# RabbitMQ Server User Data Script with Enhanced Error Handling and Verification
echo "=== RabbitMQ Server initialization starting at $(date) ===" | tee -a /var/log/rabbitmq-init.log

# Error trap: capture any command failures
trap 'echo "ERROR: Script failed at line $LINENO" | tee -a /var/log/rabbitmq-init.log; exit 1' ERR

# Configuration from Terraform variables
RABBITMQ_USER="${RABBITMQ_USER:-karate}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-karate_password}"

echo "RabbitMQ User Data Variables:" | tee -a /var/log/rabbitmq-init.log
echo "  RABBITMQ_USER: $RABBITMQ_USER" | tee -a /var/log/rabbitmq-init.log
echo "  RABBITMQ_PASSWORD: [REDACTED]" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 1: Update System Packages
# ============================================
echo "STEP 1: Updating system packages..." | tee -a /var/log/rabbitmq-init.log
apt-get update 2>&1 | tail -5 >> /var/log/rabbitmq-init.log || {
  echo "ERROR: apt-get update failed" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
apt-get upgrade -y 2>&1 | tail -5 >> /var/log/rabbitmq-init.log || {
  echo "ERROR: apt-get upgrade failed" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ System packages updated" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 2: Install Dependencies
# ============================================
echo "STEP 2: Installing dependencies..." | tee -a /var/log/rabbitmq-init.log
apt-get install -y \
    curl \
    gnupg \
    apt-transport-https \
    lsb-release \
    netcat-traditional \
    2>&1 | tail -5 >> /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to install dependencies" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ Dependencies installed" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 3: Add RabbitMQ Repository
# ============================================
echo "STEP 3: Adding RabbitMQ repository..." | tee -a /var/log/rabbitmq-init.log

# Add RabbitMQ repository key with error handling
if ! curl -1sLf https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA 2>/dev/null | \
     gpg --dearmor 2>/dev/null | tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null; then
  echo "ERROR: Failed to add RabbitMQ repository key" | tee -a /var/log/rabbitmq-init.log
  exit 1
fi

# Add RabbitMQ repository
echo "deb [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://ppa1.rabbitmq.com/ubuntu $(lsb_release -sc) main" | \
     tee /etc/apt/sources.list.d/rabbitmq.list > /dev/null || {
  echo "ERROR: Failed to add RabbitMQ source list" | tee -a /var/log/rabbitmq-init.log
  exit 1
}

apt-get update 2>&1 | tail -5 >> /var/log/rabbitmq-init.log || {
  echo "ERROR: apt-get update after adding repo failed" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ RabbitMQ repository added" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 4: Install Erlang (RabbitMQ dependency)
# ============================================
echo "STEP 4: Installing Erlang..." | tee -a /var/log/rabbitmq-init.log
apt-get install -y erlang-base erlang-asn1 erlang-crypto erlang-diameter erlang-eldap \
                  erlang-erl-docgen erlang-eunit erlang-inets erlang-jinterface erlang-mnesia \
                  erlang-odbc erlang-parsetools erlang-public-key erlang-reltool erlang-sasl \
                  erlang-snmp erlang-ssl erlang-syntax-tools erlang-tftp erlang-tools erlang-webtool \
                  erlang-wx erlang-xmerl \
                  2>&1 | tail -5 >> /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to install Erlang" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ Erlang installed" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 5: Install RabbitMQ Server
# ============================================
echo "STEP 5: Installing RabbitMQ server..." | tee -a /var/log/rabbitmq-init.log
apt-get install -y rabbitmq-server 2>&1 | tail -5 >> /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to install RabbitMQ server" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ RabbitMQ server installed" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 6: Start and Enable RabbitMQ Service
# ============================================
echo "STEP 6: Starting RabbitMQ service..." | tee -a /var/log/rabbitmq-init.log
systemctl start rabbitmq-server 2>&1 | tee -a /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to start rabbitmq-server service" | tee -a /var/log/rabbitmq-init.log
  systemctl status rabbitmq-server 2>&1 | tail -10 >> /var/log/rabbitmq-init.log
  exit 1
}
systemctl enable rabbitmq-server 2>&1 | tee -a /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to enable rabbitmq-server service" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ RabbitMQ service started and enabled" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 7: Configure Systemd File Descriptor Limits
# ============================================
echo "STEP 7: Configuring systemd file descriptor limits..." | tee -a /var/log/rabbitmq-init.log

# Create systemd service override directory
mkdir -p /etc/systemd/system/rabbitmq-server.service.d

# Create override configuration to set file descriptor limits
cat > /etc/systemd/system/rabbitmq-server.service.d/override.conf << 'EOF'
[Service]
LimitNOFILE=65536
LimitNPROC=65536
EOF

echo "✓ Created override.conf with LimitNOFILE=65536" | tee -a /var/log/rabbitmq-init.log

# Reload systemd daemon to apply override
systemctl daemon-reload 2>&1 | tee -a /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to reload systemd daemon" | tee -a /var/log/rabbitmq-init.log
  exit 1
}

# Restart RabbitMQ to apply limits
systemctl restart rabbitmq-server 2>&1 | tee -a /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to restart rabbitmq-server after applying limits" | tee -a /var/log/rabbitmq-init.log
  exit 1
}
echo "✓ Systemd limits configured and service restarted" | tee -a /var/log/rabbitmq-init.log

# Wait for service to be fully ready after restart
sleep 3
echo "✓ Waited 3 seconds for service to stabilize" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 8: Configure RabbitMQ Management Plugin
# ============================================
echo "STEP 8: Enabling RabbitMQ management plugin..." | tee -a /var/log/rabbitmq-init.log

# Enable the management plugin
rabbitmq-plugins enable rabbitmq_management 2>&1 | tee -a /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to enable rabbitmq_management plugin" | tee -a /var/log/rabbitmq-init.log
  exit 1
}

# Wait for plugin to be properly loaded
echo "Waiting 5 seconds for plugin to load..." | tee -a /var/log/rabbitmq-init.log
sleep 5

# Verify plugin is loaded
if ! rabbitmq-plugins list | grep -q "rabbitmq_management"; then
  echo "ERROR: rabbitmq_management plugin not loaded after enable" | tee -a /var/log/rabbitmq-init.log
  rabbitmq-plugins list | tee -a /var/log/rabbitmq-init.log
  exit 1
fi
echo "✓ RabbitMQ management plugin verified as loaded" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 9: Write RabbitMQ Configuration
# ============================================
echo "STEP 9: Writing RabbitMQ configuration..." | tee -a /var/log/rabbitmq-init.log

cat > /etc/rabbitmq/rabbitmq.conf << EOF
# RabbitMQ Configuration - Auto-generated by cloud-init
# Generated at: $(date)

# Memory threshold (70% of available)
vm_memory_high_watermark.relative = 0.7

# Disk free limit (in bytes)
disk_free_limit.absolute = 50MB

# AMQP listeners - bind to all interfaces
listeners.tcp.default = 5672

# Management plugin configuration - expose dashboard on all interfaces
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Channel max size
channel_max = 2048

# Enable durable queues and messages
queue_master_location = min-masters

# Logging
log.file.level = info
EOF

echo "✓ RabbitMQ configuration written" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 10: Create Custom RabbitMQ User
# ============================================
echo "STEP 10: Creating custom RabbitMQ user..." | tee -a /var/log/rabbitmq-init.log

# Set higher timeout for rabbitmqctl commands
set +e

# Add custom user
rabbitmqctl add_user "$RABBITMQ_USER" "$RABBITMQ_PASSWORD" 2>&1 | tee -a /var/log/rabbitmq-init.log
ADD_USER_RESULT=$?

set -e

# It's okay if user already exists (exit code 70 = user already exists)
if [ $ADD_USER_RESULT -ne 0 ] && [ $ADD_USER_RESULT -ne 70 ]; then
  echo "ERROR: Failed to add RabbitMQ user (exit code: $ADD_USER_RESULT)" | tee -a /var/log/rabbitmq-init.log
  exit 1
fi

# Set permissions for the custom user
if ! rabbitmqctl set_permissions -p / "$RABBITMQ_USER" ".*" ".*" ".*" 2>&1 | tee -a /var/log/rabbitmq-init.log; then
  echo "ERROR: Failed to set permissions for RabbitMQ user" | tee -a /var/log/rabbitmq-init.log
  exit 1
fi

echo "✓ Custom RabbitMQ user '$RABBITMQ_USER' created with permissions" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 11: Disable Guest User
# ============================================
echo "STEP 11: Disabling default guest user..." | tee -a /var/log/rabbitmq-init.log

# Remove guest user permissions (safer than deleting in case of rollback needs)
set +e
rabbitmqctl delete_user guest 2>&1 | tee -a /var/log/rabbitmq-init.log
set -e

echo "✓ Guest user removed" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 12: Restart with New Configuration
# ============================================
echo "STEP 12: Restarting RabbitMQ with new configuration..." | tee -a /var/log/rabbitmq-init.log

systemctl restart rabbitmq-server 2>&1 | tee -a /var/log/rabbitmq-init.log || {
  echo "ERROR: Failed to restart rabbitmq-server with new config" | tee -a /var/log/rabbitmq-init.log
  systemctl status rabbitmq-server 2>&1 | tail -10 >> /var/log/rabbitmq-init.log
  exit 1
}

echo "✓ RabbitMQ restarted" | tee -a /var/log/rabbitmq-init.log
sleep 2

# ============================================
# STEP 13: Verify RabbitMQ is Listening
# ============================================
echo "STEP 13: Verifying RabbitMQ listening on ports..." | tee -a /var/log/rabbitmq-init.log

# Check if AMQP port (5672) is listening
if ! timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/5672' 2>/dev/null; then
  echo "ERROR: RabbitMQ AMQP port (5672) not listening" | tee -a /var/log/rabbitmq-init.log
  ss -tlnp 2>/dev/null | grep -E '5672|15672' | tee -a /var/log/rabbitmq-init.log || true
  exit 1
fi
echo "✓ RabbitMQ AMQP port (5672) is listening" | tee -a /var/log/rabbitmq-init.log

# Check if management port (15672) is listening
if ! timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/15672' 2>/dev/null; then
  echo "ERROR: RabbitMQ management port (15672) not listening" | tee -a /var/log/rabbitmq-init.log
  ss -tlnp 2>/dev/null | grep -E '5672|15672' | tee -a /var/log/rabbitmq-init.log || true
  exit 1
fi
echo "✓ RabbitMQ management port (15672) is listening" | tee -a /var/log/rabbitmq-init.log

# ============================================
# STEP 14: Health Check Loop with Verification
# ============================================
echo "STEP 14: Running health check loop..." | tee -a /var/log/rabbitmq-init.log

MAX_ATTEMPTS=60
ATTEMPT=0
HEALTH_CHECK_SUCCESS=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  
  # Check if RabbitMQ is operational via CLI
  if rabbitmqctl status > /dev/null 2>&1; then
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: RabbitMQ status check passed" >> /var/log/rabbitmq-init.log
    
    # Try to list queues as additional verification
    if rabbitmqctl list_queues > /dev/null 2>&1; then
      echo "✓ RabbitMQ is fully operational (queues accessible)" | tee -a /var/log/rabbitmq-init.log
      HEALTH_CHECK_SUCCESS=true
      break
    fi
  else
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
      echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: RabbitMQ status check in progress..." | tee -a /var/log/rabbitmq-init.log
    fi
  fi
  
  # Wait before next attempt
  if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
    sleep 2
  fi
done

if [ "$HEALTH_CHECK_SUCCESS" = false ]; then
  echo "ERROR: RabbitMQ health check failed after $((MAX_ATTEMPTS * 2)) seconds" | tee -a /var/log/rabbitmq-init.log
  echo "RabbitMQ status output:" | tee -a /var/log/rabbitmq-init.log
  rabbitmqctl status 2>&1 | tail -20 >> /var/log/rabbitmq-init.log
  exit 1
fi

# ============================================
# STEP 15: Final Verification
# ============================================
echo "STEP 15: Final verification..." | tee -a /var/log/rabbitmq-init.log

# Verify port binding with netstat
echo "Active listening ports:" | tee -a /var/log/rabbitmq-init.log
ss -tlnp 2>/dev/null | grep -E 'tcp.*:(5672|15672)' | tee -a /var/log/rabbitmq-init.log || true

# Verify systemd service is active
if systemctl is-active --quiet rabbitmq-server; then
  echo "✓ RabbitMQ systemd service is active" | tee -a /var/log/rabbitmq-init.log
else
  echo "ERROR: RabbitMQ systemd service is not active" | tee -a /var/log/rabbitmq-init.log
  systemctl status rabbitmq-server 2>&1 | tail -10 >> /var/log/rabbitmq-init.log
  exit 1
fi

# Get RabbitMQ internal details
echo "RabbitMQ users:" | tee -a /var/log/rabbitmq-init.log
rabbitmqctl list_users 2>&1 | tee -a /var/log/rabbitmq-init.log

echo "RabbitMQ memory usage:" | tee -a /var/log/rabbitmq-init.log
rabbitmqctl status 2>&1 | grep -i memory | tee -a /var/log/rabbitmq-init.log || true

# ============================================
# Initialization Complete
# ============================================
echo "" | tee -a /var/log/rabbitmq-init.log
echo "=== RabbitMQ Server initialization completed successfully at $(date) ===" | tee -a /var/log/rabbitmq-init.log
echo "✓ RabbitMQ is ready for connections" | tee -a /var/log/rabbitmq-init.log
echo "  - AMQP endpoint: 0.0.0.0:5672" | tee -a /var/log/rabbitmq-init.log
echo "  - Management UI: http://0.0.0.0:15672" | tee -a /var/log/rabbitmq-init.log
echo "  - Default user: $RABBITMQ_USER" | tee -a /var/log/rabbitmq-init.log
echo "  - Logs: /var/log/rabbitmq/rabbit@*.log" | tee -a /var/log/rabbitmq-init.log
echo "  - Cloud-init logs: /var/log/rabbitmq-init.log" | tee -a /var/log/rabbitmq-init.log
echo "" | tee -a /var/log/rabbitmq-init.log

# Exit with success code to signal cloud-init completion
exit 0
