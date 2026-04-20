#!/bin/bash
set -e

# PostgreSQL Server User Data Script
echo "Starting PostgreSQL Server initialization..."

# Update system packages
apt-get update
apt-get upgrade -y

# Install PostgreSQL
apt-get install -y \
    postgresql \
    postgresql-contrib \
    postgresql-client \
    postgresql-client-common \
    build-essential \
    libpq-dev

echo "Installed PostgreSQL"

# Make sure PostgreSQL service is running
systemctl start postgresql
systemctl enable postgresql

# Create database and user
sudo -u postgres psql << SQL
-- Create database
CREATE DATABASE ${DB_NAME};

-- Create user with password
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';

-- Grant privileges
ALTER ROLE ${DB_USER} SET client_encoding TO 'utf8';
ALTER ROLE ${DB_USER} SET default_transaction_isolation TO 'read committed';
ALTER ROLE ${DB_USER} SET default_transaction_deferrable TO on;
ALTER ROLE ${DB_USER} SET default_transaction_read_only TO off;

-- Grant all privileges on the database
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the database and grant schema privileges
\connect ${DB_NAME}
GRANT ALL PRIVILEGES ON SCHEMA public TO ${DB_USER};
SQL

echo "Created database and user"

# Configure PostgreSQL to accept connections from other servers
# Backup original file
cp /etc/postgresql/*/main/pg_hba.conf /etc/postgresql/*/main/pg_hba.conf.backup

# Update pg_hba.conf to allow TCP connections from the VPC
cat >> /etc/postgresql/*/main/pg_hba.conf << EOF

# Allow connections from API and Worker servers in the VPC
host    ${DB_NAME}    ${DB_USER}    10.0.0.0/16    md5
host    all           all          10.0.0.0/16    md5
EOF

# Update postgresql.conf to listen on all network interfaces
POSTGRES_CONF="/etc/postgresql/*/main/postgresql.conf"
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" $POSTGRES_CONF

echo "Configured PostgreSQL for network access"

# Restart PostgreSQL to apply configuration
systemctl restart postgresql

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
        echo "✓ PostgreSQL is ready"
        break
    fi
    echo "  Attempting... ($i/30)"
    sleep 2
done

# Initialize database schema
# This script will download and run the init.sql from the repository
SCHEMA_DIR="/tmp"
DB_INIT_SQL="/tmp/init.sql"

# Create the init.sql with the schema
cat > $DB_INIT_SQL << 'SCHEMA_EOF'
CREATE TABLE IF NOT EXISTS combats (
    id SERIAL PRIMARY KEY,
    time VARCHAR(50),
    participant_red VARCHAR(100),
    participant_blue VARCHAR(100),
    points_red INT,
    points_blue INT,
    fouls_red INT,
    fouls_blue INT,
    judges TEXT,
    status VARCHAR(20),
    date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_combats_status ON combats(status);
CREATE INDEX IF NOT EXISTS idx_combats_date ON combats(date);

-- Optionally create the Orders table if mentioned in requirements
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    combat_id INT REFERENCES combats(id),
    consumer_id VARCHAR(100),
    action VARCHAR(50),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_orders_combat_id ON orders(combat_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
SCHEMA_EOF

# Run the schema initialization
sudo -u postgres psql ${DB_NAME} < $DB_INIT_SQL

echo "Initialized database schema"

# Verify the schema was created
sudo -u postgres psql ${DB_NAME} -c "\dt"

# Set up backup directory (optional)
mkdir -p /var/backups/postgresql
chown postgres:postgres /var/backups/postgresql
chmod 700 /var/backups/postgresql

echo "Created backup directory"

# Check PostgreSQL status
sudo -u postgres psql --version

echo "PostgreSQL Server initialization complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Wait 30-60 seconds for full initialization before connecting."
