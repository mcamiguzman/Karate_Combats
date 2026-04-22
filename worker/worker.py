import pika
import json
import psycopg2
import time
import os

# Environment variables with defaults for local development
DB_HOST = os.environ.get("DB_HOST", "db")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "admin")
DB_NAME = os.environ.get("DB_NAME", "combats")

RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.environ.get("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "karate")
RABBITMQ_PASSWORD = os.environ.get("RABBITMQ_PASSWORD", "karate_password")

# Track service readiness and startup timing
_db_connected = False
_rabbitmq_connected = False
_startup_time = time.time()
_STARTUP_GRACE_PERIOD = 120  # Give services 2 minutes to stabilize

# Circuit breaker state for resilience
_db_failures = 0
_rabbitmq_failures = 0
_DB_FAILURE_THRESHOLD = 5
_RABBITMQ_FAILURE_THRESHOLD = 5
_CIRCUIT_BREAKER_RESET_TIME = 30
_last_db_failure_time = None
_last_rabbitmq_failure_time = None


def is_startup_grace_period():
    """Check if we're still in the startup grace period"""
    return (time.time() - _startup_time) < _STARTUP_GRACE_PERIOD


def wait_for_rabbitmq():
    """
    Wait for RabbitMQ with exponential backoff and circuit breaker.
    During startup grace period, retries are more lenient.
    """
    global _rabbitmq_connected, _rabbitmq_failures, _last_rabbitmq_failure_time
    
    max_retries = 3
    max_total_time = 30
    start_time = time.time()
    backoff_delays = [2, 4, 8]
    
    for attempt in range(max_retries):
        try:
            credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(host=RABBITMQ_HOST, port=RABBITMQ_PORT, credentials=credentials)
            )
            if not _rabbitmq_connected:
                _rabbitmq_connected = True
                print(f"Connected to RabbitMQ (attempt {attempt + 1}/{max_retries})")
            
            # Reset failure counter on success
            _rabbitmq_failures = 0
            _last_rabbitmq_failure_time = None
            return connection
        
        except pika.exceptions.AMQPConnectionError as e:
            _rabbitmq_failures += 1
            _last_rabbitmq_failure_time = time.time()
            elapsed = time.time() - start_time
            
            print(f"RabbitMQ connection attempt {attempt + 1}/{max_retries} failed (failures: {_rabbitmq_failures}): {str(e)}")
            
            if elapsed >= max_total_time:
                print(f"RabbitMQ retry timeout exceeded ({elapsed:.1f}s >= {max_total_time}s)")
                raise
            
            if attempt < max_retries - 1:
                delay = backoff_delays[attempt]
                if elapsed + delay > max_total_time:
                    print(f"Next retry would exceed max time, giving up")
                    raise
                print(f"Waiting {delay}s before retry...")
                time.sleep(delay)
            else:
                raise


def get_db():
    """
    Get database connection with exponential backoff and circuit breaker.
    During startup grace period, retries are more lenient.
    """
    global _db_connected, _db_failures, _last_db_failure_time
    
    max_retries = 3
    max_total_time = 30
    start_time = time.time()
    backoff_delays = [2, 4, 8]
    
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
            if not _db_connected:
                _db_connected = True
                print(f"Connected to PostgreSQL (attempt {attempt + 1}/{max_retries})")
            
            # Reset failure counter on success
            _db_failures = 0
            _last_db_failure_time = None
            return conn
        
        except psycopg2.OperationalError as e:
            _db_failures += 1
            _last_db_failure_time = time.time()
            elapsed = time.time() - start_time
            
            print(f"PostgreSQL connection attempt {attempt + 1}/{max_retries} failed (failures: {_db_failures}): {str(e)}")
            
            if elapsed >= max_total_time:
                print(f"PostgreSQL retry timeout exceeded ({elapsed:.1f}s >= {max_total_time}s)")
                raise
            
            if attempt < max_retries - 1:
                delay = backoff_delays[attempt]
                if elapsed + delay > max_total_time:
                    print(f"Next retry would exceed max time, giving up")
                    raise
                print(f"Waiting {delay}s before retry...")
                time.sleep(delay)
            else:
                raise


def callback(ch, method, properties, body):
    """Process messages from RabbitMQ queue"""

    print("Message received")

    message = json.loads(body)
    action = message.get("action")
    data = message.get("data", {})

    try:
        conn = get_db()
        cur = conn.cursor()

        if action == "create":
            print("Processing CREATE action for combat")
            
            cur.execute("""
            INSERT INTO combats
            (time, participant_red, participant_blue,
            points_red, points_blue, fouls_red, fouls_blue, judges, status)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'created')
            RETURNING id
            """, (
                data.get("time"),
                data.get("participant_red"),
                data.get("participant_blue"),
                int(data.get("points_red", 0)),
                int(data.get("points_blue", 0)),
                int(data.get("fouls_red", 0)),
                int(data.get("fouls_blue", 0)),
                data.get("judges")
            ))

            combat_id = cur.fetchone()[0]

            # Create order record
            cur.execute("""
            INSERT INTO orders
            (combat_id, consumer_id, action, action_details, status)
            VALUES (%s, %s, %s, %s, 'completed')
            """, (
                combat_id,
                data.get("consumer_id", "system"),
                "create",
                json.dumps(data)
            ))

            conn.commit()
            print(f"Combat {combat_id} created and stored in database")

        elif action == "update":
            print(f"Processing UPDATE action for combat {data.get('combat_id')}")

            combat_id = data.get("combat_id")
            
            # Build dynamic SQL for updates
            update_fields = []
            update_values = []

            if data.get("points_red") is not None:
                update_fields.append("points_red = %s")
                update_values.append(int(data.get("points_red")))
            
            if data.get("points_blue") is not None:
                update_fields.append("points_blue = %s")
                update_values.append(int(data.get("points_blue")))
            
            if data.get("fouls_red") is not None:
                update_fields.append("fouls_red = %s")
                update_values.append(int(data.get("fouls_red")))
            
            if data.get("fouls_blue") is not None:
                update_fields.append("fouls_blue = %s")
                update_values.append(int(data.get("fouls_blue")))
            
            if data.get("status") is not None:
                update_fields.append("status = %s")
                update_values.append(data.get("status"))

            if data.get("judges") is not None:
                update_fields.append("judges = %s")
                update_values.append(data.get("judges"))

            if update_fields:
                update_values.append(combat_id)
                sql = f"UPDATE combats SET {', '.join(update_fields)} WHERE id = %s"
                cur.execute(sql, update_values)

                # Create order record
                cur.execute("""
                INSERT INTO orders
                (combat_id, consumer_id, action, action_details, status)
                VALUES (%s, %s, %s, %s, 'completed')
                """, (
                    combat_id,
                    data.get("consumer_id", "system"),
                    "update",
                    json.dumps(data)
                ))

                conn.commit()
                print(f"Combat {combat_id} updated successfully")
            else:
                print(f"No update fields provided for combat {combat_id}")

        elif action == "delete":
            print(f"Processing DELETE action for combat {data.get('combat_id')}")

            combat_id = data.get("combat_id")

            # Verify combat exists
            cur.execute("SELECT id FROM combats WHERE id = %s", (combat_id,))
            if not cur.fetchone():
                print(f"Combat {combat_id} not found")
            else:
                # Create order record before deletion
                cur.execute("""
                INSERT INTO orders
                (combat_id, consumer_id, action, action_details, status)
                VALUES (%s, %s, %s, %s, 'completed')
                """, (
                    combat_id,
                    data.get("consumer_id", "system"),
                    "delete",
                    json.dumps({"combat_id": combat_id})
                ))

                # Delete combat (cascade deletes related orders due to FK constraint)
                cur.execute("DELETE FROM combats WHERE id = %s", (combat_id,))
                conn.commit()
                print(f"Combat {combat_id} deleted successfully")

        else:
            print(f"Unknown action: {action}")

        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error processing message: {str(e)}")
        # Acknowledge message even on error to avoid infinite retry loops
    
    finally:
        ch.basic_ack(delivery_tag=method.delivery_tag)


print("Worker starting...")

connection = wait_for_rabbitmq()

channel = connection.channel()

channel.queue_declare(queue="combat_queue")

channel.basic_consume(
    queue="combat_queue",
    on_message_callback=callback
)

print("Worker waiting for messages...")

channel.start_consuming()
