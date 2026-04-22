from flask import Flask, render_template, request, jsonify
import pika
import json
import psycopg2
import os
from flasgger import Swagger
import time
import traceback

# Ensure Flask can find templates correctly
template_dir = os.path.join(os.path.dirname(__file__), 'templates')
app = Flask(__name__, template_folder=template_dir)
swagger = Swagger(app)

# Environment variables with defaults for local development
DB_HOST = os.environ.get("DB_HOST", "db")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "admin")
DB_NAME = os.environ.get("DB_NAME", "combats")

RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.environ.get("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "karate")
RABBITMQ_PASSWORD = os.environ.get("RABBITMQ_PASSWORD", "karate_password")

# Track service readiness
_db_connected = False
_rabbitmq_connected = False
_startup_time = time.time()
_STARTUP_GRACE_PERIOD = 120  # Give services 2 minutes to stabilize

# Circuit breaker state for resilience
_db_failures = 0
_rabbitmq_failures = 0
_DB_FAILURE_THRESHOLD = 5  # Consecutive failures before circuit opens
_RABBITMQ_FAILURE_THRESHOLD = 5
_CIRCUIT_BREAKER_RESET_TIME = 30  # Seconds before attempting retry after circuit opens
_last_db_failure_time = None
_last_rabbitmq_failure_time = None


def is_startup_grace_period():
    """Check if we're still in the startup grace period"""
    return (time.time() - _startup_time) < _STARTUP_GRACE_PERIOD


def get_db():
    """Get database connection with exponential backoff and circuit breaker"""
    global _db_connected, _db_failures, _last_db_failure_time
    
    # Check circuit breaker - fast fail if too many recent failures
    if _db_failures >= _DB_FAILURE_THRESHOLD:
        time_since_last_failure = time.time() - _last_db_failure_time if _last_db_failure_time else 0
        if time_since_last_failure < _CIRCUIT_BREAKER_RESET_TIME:
            app.logger.warning(f"Database circuit breaker OPEN: {_db_failures} consecutive failures. Skipping reconnect attempt.")
            raise Exception(f"Database circuit breaker open. Failed {_db_failures} times. Retry in {_CIRCUIT_BREAKER_RESET_TIME - time_since_last_failure:.1f}s")
        else:
            # Reset circuit breaker after grace period
            app.logger.info("Database circuit breaker RESET - attempting reconnection")
            _db_failures = 0
            _last_db_failure_time = None
    
    max_retries = 3
    max_total_time = 30  # Don't retry longer than 30 seconds total
    start_time = time.time()
    
    # Exponential backoff: 2, 4, 8 seconds
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
                app.logger.info(f"Successfully connected to PostgreSQL (attempt {attempt + 1}/{max_retries})")
            
            # Reset failure counter on success
            _db_failures = 0
            _last_db_failure_time = None
            return conn
        
        except psycopg2.OperationalError as e:
            _db_failures += 1
            _last_db_failure_time = time.time()
            elapsed = time.time() - start_time
            
            app.logger.warning(f"PostgreSQL connection attempt {attempt + 1}/{max_retries} failed (failures: {_db_failures}/{_DB_FAILURE_THRESHOLD}): {str(e)}")
            
            # Check if we've exceeded max retry time
            if elapsed >= max_total_time:
                app.logger.error(f"PostgreSQL retry timeout exceeded ({elapsed:.1f}s >= {max_total_time}s)")
                raise
            
            # Wait with exponential backoff before next attempt
            if attempt < max_retries - 1:
                delay = backoff_delays[attempt]
                if elapsed + delay > max_total_time:
                    # Would exceed max time, so don't retry
                    app.logger.error(f"Next retry would exceed max time ({elapsed + delay:.1f}s > {max_total_time}s), giving up")
                    raise
                app.logger.info(f"Waiting {delay}s before retry...")
                time.sleep(delay)
            else:
                raise


def send_to_queue(message):
    """Send message to RabbitMQ with exponential backoff and circuit breaker"""
    global _rabbitmq_connected, _rabbitmq_failures, _last_rabbitmq_failure_time
    
    # Check circuit breaker - fast fail if too many recent failures
    if _rabbitmq_failures >= _RABBITMQ_FAILURE_THRESHOLD:
        time_since_last_failure = time.time() - _last_rabbitmq_failure_time if _last_rabbitmq_failure_time else 0
        if time_since_last_failure < _CIRCUIT_BREAKER_RESET_TIME:
            app.logger.warning(f"RabbitMQ circuit breaker OPEN: {_rabbitmq_failures} consecutive failures. Skipping reconnect attempt.")
            raise Exception(f"RabbitMQ circuit breaker open. Failed {_rabbitmq_failures} times. Retry in {_CIRCUIT_BREAKER_RESET_TIME - time_since_last_failure:.1f}s")
        else:
            # Reset circuit breaker after grace period
            app.logger.info("RabbitMQ circuit breaker RESET - attempting reconnection")
            _rabbitmq_failures = 0
            _last_rabbitmq_failure_time = None
    
    max_retries = 3
    max_total_time = 30  # Don't retry longer than 30 seconds total
    start_time = time.time()
    
    # Exponential backoff: 2, 4, 8 seconds
    backoff_delays = [2, 4, 8]
    
    for attempt in range(max_retries):
        try:
            credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(host=RABBITMQ_HOST, port=RABBITMQ_PORT, credentials=credentials)
            )
            channel = connection.channel()
            channel.queue_declare(queue="combat_queue", durable=True)
            channel.basic_publish(
                exchange="",
                routing_key="combat_queue",
                body=json.dumps(message),
                properties=pika.BasicProperties(delivery_mode=2)
            )
            connection.close()
            
            if not _rabbitmq_connected:
                _rabbitmq_connected = True
                app.logger.info(f"Successfully connected to RabbitMQ (attempt {attempt + 1}/{max_retries})")
            
            # Reset failure counter on success
            _rabbitmq_failures = 0
            _last_rabbitmq_failure_time = None
            return
        
        except pika.exceptions.AMQPError as e:
            _rabbitmq_failures += 1
            _last_rabbitmq_failure_time = time.time()
            elapsed = time.time() - start_time
            
            app.logger.warning(f"RabbitMQ connection attempt {attempt + 1}/{max_retries} failed (failures: {_rabbitmq_failures}/{_RABBITMQ_FAILURE_THRESHOLD}): {str(e)}")
            
            # Check if we've exceeded max retry time
            if elapsed >= max_total_time:
                app.logger.error(f"RabbitMQ retry timeout exceeded ({elapsed:.1f}s >= {max_total_time}s)")
                raise
            
            # Wait with exponential backoff before next attempt
            if attempt < max_retries - 1:
                delay = backoff_delays[attempt]
                if elapsed + delay > max_total_time:
                    # Would exceed max time, so don't retry
                    app.logger.error(f"Next retry would exceed max time ({elapsed + delay:.1f}s > {max_total_time}s), giving up")
                    raise
                app.logger.info(f"Waiting {delay}s before retry...")
                time.sleep(delay)
            else:
                raise


@app.route("/")
def index():
    """
    Root endpoint to access the web interface
    ---
    responses:
      200:
        description: Web interface loaded successfully
      500:
        description: Internal server error
    """
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("SELECT * FROM combats ORDER BY id DESC")
        combats = cur.fetchall()

        cur.close()
        conn.close()

        return render_template("index.html", combats=combats)
    except FileNotFoundError as e:
        # Template not found
        error_msg = f"Template not found: {str(e)}. Template directory: {template_dir}"
        app.logger.error(error_msg)
        return f"<h1>500 Error: Template Not Found</h1><p>{error_msg}</p>", 500
    except Exception as e:
        # Other errors (database, etc.)
        error_msg = f"Error retrieving combats: {str(e)}"
        app.logger.error(f"{error_msg}\n{traceback.format_exc()}")
        return f"<h1>500 Error: Internal Server Error</h1><p>{error_msg}</p>", 500


@app.route("/combats", methods=["GET"])
def get_combats():
    """
    Get all combats as JSON
    ---
    responses:
      200:
        description: List of all combats retrieved successfully
      500:
        description: Internal server error
    """
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("SELECT * FROM combats ORDER BY id DESC")
        combats = cur.fetchall()

        cur.close()
        conn.close()

        return {
            "combats": [
                {
                    "id": combat[0],
                    "time": combat[1],
                    "participant_red": combat[2],
                    "participant_blue": combat[3],
                    "points_red": combat[4],
                    "points_blue": combat[5],
                    "fouls_red": combat[6],
                    "fouls_blue": combat[7],
                    "judges": combat[8],
                    "status": combat[9],
                    "date": str(combat[10]) if combat[10] else None
                }
                for combat in combats
            ]
        }, 200
    except Exception as e:
        error_msg = f"Error retrieving combats: {str(e)}"
        app.logger.error(f"{error_msg}\n{traceback.format_exc()}")
        return {"error": error_msg}, 500


@app.route("/combats", methods=["POST"])
def create_combat():
    """
    Create a new combat record
    ---
    parameters:
      - name: time
        in: formData
        type: string
        required: true
      - name: participant_red
        in: formData
        type: string
        required: true
      - name: participant_blue
        in: formData
        type: string
        required: true
      - name: points_red
        in: formData
        type: integer
      - name: points_blue
        in: formData
        type: integer
      - name: fouls_red
        in: formData
        type: integer
      - name: fouls_blue
        in: formData
        type: integer
      - name: judges
        in: formData
        type: string
    responses:
      202:
        description: Combat record sent to queue for creation
      400:
        description: Missing required fields
    """
    
    # Validate required fields
    required_fields = ["time", "participant_red", "participant_blue", "judges"]
    missing_fields = [field for field in required_fields if field not in request.form]
    
    if missing_fields:
        return {
            "error": "Missing required fields",
            "missing_fields": missing_fields,
            "expected_fields": {
                "required": required_fields,
                "optional": ["points_red", "points_blue", "fouls_red", "fouls_blue"]
            }
        }, 400

    try:
        data = {
            "time": request.form["time"],
            "participant_red": request.form["participant_red"],
            "participant_blue": request.form["participant_blue"],
            "points_red": request.form.get("points_red", 0),
            "points_blue": request.form.get("points_blue", 0),
            "fouls_red": request.form.get("fouls_red", 0),
            "fouls_blue": request.form.get("fouls_blue", 0),
            "judges": request.form["judges"]
        }

        message = {
            "action": "create",
            "data": data
        }

        send_to_queue(message)
        return {"status": "success", "message": "Combat queued for creation"}, 202
    except Exception as e:
        app.logger.error(f"Error creating combat: {str(e)}\n{traceback.format_exc()}")
        return {"error": f"Failed to create combat: {str(e)}"}, 500


@app.route("/combats/<int:id>", methods=["PUT"])
def update_combat(id):
    """
    Update an existing combat record
    ---
    parameters:
      - name: id
        in: path
        type: integer
        required: true
      - name: points_red
        in: formData
        type: integer
      - name: points_blue
        in: formData
        type: integer
      - name: fouls_red
        in: formData
        type: integer
      - name: fouls_blue
        in: formData
        type: integer
      - name: status
        in: formData
        type: string
      - name: judges
        in: formData
        type: string
    responses:
      202:
        description: Combat record update request sent
      404:
        description: Combat not found
    """

    data = {
        "id": id,
        "points_red": request.form.get("points_red"),
        "points_blue": request.form.get("points_blue"),
        "fouls_red": request.form.get("fouls_red"),
        "fouls_blue": request.form.get("fouls_blue"),
        "status": request.form.get("status", "updated"),
        "judges": request.form.get("judges")
    }

    message = {
        "action": "update",
        "data": data
    }

    send_to_queue(message)

    return {"status": "success", "message": f"Combat {id} queued for update"}, 202


@app.route("/combats/<int:id>", methods=["DELETE"])
def delete_combat(id):
    """
    Delete a combat record
    ---
    parameters:
      - name: id
        in: path
        type: integer
        required: true
    responses:
      202:
        description: Combat record deletion request sent
      404:
        description: Combat not found
    """

    message = {
        "action": "delete",
        "data": {
            "id": id
        }
    }

    send_to_queue(message)

    return {"status": "success", "message": f"Combat {id} queued for deletion"}, 202


@app.route("/orders", methods=["GET"])
def get_orders():
    """
    Get all orders
    ---
    responses:
      200:
        description: List of orders retrieved successfully
    """

    conn = get_db()
    cur = conn.cursor()

    cur.execute("""
        SELECT id, combat_id, consumer_id, action, status, created_at 
        FROM orders ORDER BY created_at DESC
    """)
    orders = cur.fetchall()

    cur.close()
    conn.close()

    return {
        "orders": [
            {
                "id": order[0],
                "combat_id": order[1],
                "consumer_id": order[2],
                "action": order[3],
                "status": order[4],
                "created_at": str(order[5])
            }
            for order in orders
        ]
    }, 200


@app.route("/health", methods=["GET"])
def health_check():
    """
    Health check endpoint for load balancer
    ---
    responses:
      200:
        description: Service is healthy
      503:
        description: Service is unhealthy
    """
    
    # Basic check - if we got here, the Flask app is running
    health_status = {
        "status": "healthy",
        "service": "karate-api"
    }
    
    # Try to connect to database, but don't fail if unavailable during startup
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        health_status["database"] = "connected"
        health_status["rabbitmq"] = "connected" if _rabbitmq_connected else "untested"
        return health_status, 200
    except Exception as e:
        # Check if we're still in startup grace period
        in_grace_period = is_startup_grace_period()
        
        # Log the error
        app.logger.warning(f"Database connection failed: {str(e)}")
        health_status["database"] = "unavailable"
        health_status["database_error"] = str(e)
        health_status["startup_grace_period"] = in_grace_period
        
        # Return 200 during grace period to allow stabilization, 503 after
        if in_grace_period:
            return health_status, 200
        else:
            return health_status, 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)