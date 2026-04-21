#!/bin/bash
# PostgreSQL Permission Diagnostic Script
# Use this to diagnose what permissions are actually set
# Run on PostgreSQL instance via SSH: bash diagnose-postgresql-permissions.sh

set -e

# Read environment variables or use defaults
DB_NAME=${DB_NAME:-"combats"}
DB_USER=${DB_USER:-"admin"}

echo "========================================"
echo "PostgreSQL Permission Diagnostic"
echo "========================================"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""

# Function to run SQL as postgres user
run_as_postgres() {
    sudo -u postgres psql -d "$DB_NAME" -c "$1"
}

echo "=== Database and User Info ==="
run_as_postgres "\du"
echo ""

echo "=== Table Definitions ==="
run_as_postgres "\dt"
echo ""

echo "=== Current Table Owners ==="
run_as_postgres "
SELECT schemaname, tablename, tableowner 
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;
"
echo ""

echo "=== Default Privileges ==="
run_as_postgres "
SELECT defaclnamespace::regnamespace as schema,
       defacluser::regrole as role,
       defaclobjtype as object_type,
       defaclacl as privileges
FROM pg_default_acl
WHERE defaclnamespace::regnamespace = 'public'::regnamespace;
"
echo ""

echo "=== Current Table Privileges ==="
run_as_postgres "
SELECT 
    grantee,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
ORDER BY table_name, grantee, privilege_type;
"
echo ""

echo "=== Test: Can $DB_USER SELECT from combats? ==="
RESULT=$(sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "SELECT COUNT(*) FROM combats;" 2>&1)
echo "Result: $RESULT"
echo ""

echo "=== Test: Can $DB_USER INSERT into combats? ==="
TEST_RESULT=$(sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "INSERT INTO combats (time, participant_red, participant_blue, judges) VALUES ('diagnostic-test', 'test', 'test', 'test') RETURNING id;" 2>&1)
echo "Result: $TEST_RESULT"
if [[ $TEST_RESULT == *"1 row"* ]] || [[ $TEST_RESULT == *" 1"* ]]; then
    # Cleanup
    sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "DELETE FROM combats WHERE time = 'diagnostic-test';" 2>&1 > /dev/null
    echo "✓ Inserted successfully"
else
    echo "✗ Insert failed"
fi
echo ""

echo "=== Sequence Privileges ==="
run_as_postgres "
SELECT schemaname, sequencename, sequenceowner 
FROM pg_sequences 
WHERE schemaname = 'public';
"
echo ""

echo "========================================"
echo "Diagnostic complete - Review above to identify permission issues"
echo "========================================"
