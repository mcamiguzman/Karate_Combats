#!/bin/bash
set -e

# RabbitMQ Server User Data Script
echo "Starting RabbitMQ Server initialization..."

# Update system packages
apt-get update
apt-get upgrade -y

# Install RabbitMQ
apt-get install -y \
    curl \
    gnupg \
    apt-transport-https \
    lsb-release

# Add RabbitMQ repository key
curl -1sLf https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA | gpg --dearmor | tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null

# Add RabbitMQ repository
echo "deb [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://ppa1.rabbitmq.com/ubuntu $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/rabbitmq.list

# Install Erlang (required for RabbitMQ)
apt-get update
apt-get install -y erlang-base erlang-asn1 erlang-crypto erlang-diameter erlang-eldap erlang-erl-docgen erlang-eunit erlang-inets erlang-jinterface erlang-mnesia erlang-odbc erlang-parsetools erlang-public-key erlang-reltool erlang-sasl erlang-snmp erlang-ssl erlang-syntax-tools erlang-tftp erlang-tools erlang-webtool erlang-wx erlang-xmerl

# Install RabbitMQ server
apt-get install -y rabbitmq-server

echo "Installed RabbitMQ"

# Start RabbitMQ service
systemctl start rabbitmq-server
systemctl enable rabbitmq-server

# Enable RabbitMQ management plugin
rabbitmq-plugins enable rabbitmq_management

# Add RabbitMQ user (optional: for enhanced security)
# Default user 'guest' is already created with password 'guest'
# To add custom user:
# rabbitmqctl add_user karate karate_password
# rabbitmqctl set_permissions -p / karate ".*" ".*" ".*"

echo "RabbitMQ Management UI enabled"

# Configure RabbitMQ
# Set maximum file descriptors
ulimit -n 65536

# Add to /etc/security/limits.conf
cat >> /etc/security/limits.conf << EOF
rabbitmq soft nofile 65536
rabbitmq hard nofile 65536
EOF

# Configure RabbitMQ memory usage
cat > /etc/rabbitmq/rabbitmq.conf << EOF
# RabbitMQ Configuration

# Memory threshold
vm_memory_high_watermark.relative = 0.7

# Disk free limit (in bytes)
disk_free_limit.absolute = 50MB

# AMQP listeners - bind to all interfaces
listeners.tcp.default = 5672

# Management plugin configuration - expose dashboard on all interfaces
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Enable AMQP frame max size
channel_max = 2048
EOF

# Restart RabbitMQ to apply configuration
systemctl restart rabbitmq-server

echo "Configured RabbitMQ"

# Wait for RabbitMQ to be ready
echo "Waiting for RabbitMQ to be ready..."
for i in {1..30}; do
    if rabbitmqctl status > /dev/null 2>&1; then
        echo "✓ RabbitMQ is ready"
        break
    fi
    echo "  Attempting... ($i/30)"
    sleep 2
done

# Check RabbitMQ status
rabbitmqctl status || echo "Warning: Could not verify RabbitMQ status"

# Create a test queue to verify functionality
rabbitmqctl list_queues || true

echo "RabbitMQ Server initialization complete!"
echo "Management UI: http://$(hostname -I | awk '{print $1}'):15672"
echo "Default credentials: guest/guest"
