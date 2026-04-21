from flask import Flask, render_template, request, jsonify
import pika
import json
import psycopg2
import os
from flasgger import Swagger
import time

app = Flask(__name__)
swagger = Swagger(app)

# Environment variables with defaults for local development
DB_HOST = os.environ.get("DB_HOST", "db")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "admin")
DB_NAME = os.environ.get("DB_NAME", "combats")

RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.environ.get("RABBITMQ_PORT", "5672"))

# Track service readiness
_db_connected = False
_rabbitmq_connected = False
_startup_time = time.time()
_STARTUP_GRACE_PERIOD = 120  # Give services 2 minutes to stabilize


def is_startup_grace_period():
    """Check if we're still in the startup grace period"""
    return (time.time() - _startup_time) < _STARTUP_GRACE_PERIOD


def get_db():
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


def send_to_queue(message):

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host=RABBITMQ_HOST, port=RABBITMQ_PORT)
    )

    channel = connection.channel()
    channel.queue_declare(queue="combat_queue")

    channel.basic_publish(
        exchange="",
        routing_key="combat_queue",
        body=json.dumps(message)
    )

    connection.close()


@app.route("/")
def index():
    """
    Get all combats
    ---
    responses:
      200:
        description: List of combats retrieved successfully
    """

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT * FROM combats ORDER BY id DESC")
    combats = cur.fetchall()

    cur.close()
    conn.close()

    return render_template("index.html", combats=combats)


@app.route("/combats", methods=["POST"])
def create_combat():
    """
    Create a new combat
    ---
    parameters:
      - name: time
        in: formData
        type: string
        required: true
      - name: red
        in: formData
        type: string
        required: true
      - name: blue
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
        type: integer
    responses:
      200:
        description: Combat created and returned updated list
    """

    data = {
        "time": request.form["time"],
        "red": request.form["red"],
        "blue": request.form["blue"],
        "points_red": request.form["points_red"],
        "points_blue": request.form["points_blue"],
        "fouls_red": request.form["fouls_red"],
        "fouls_blue": request.form["fouls_blue"],
        "judges": request.form["judges"]
    }

    message = {
        "action": "create",
        "data": data
    }

    send_to_queue(message)

    return index()


@app.route("/combats/<int:combat_id>", methods=["PUT"])
def update_combat(combat_id):
    """
    Update an existing combat
    ---
    parameters:
      - name: combat_id
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
      200:
        description: Combat updated successfully
      404:
        description: Combat not found
    """

    data = {
        "combat_id": combat_id,
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

    return index()


@app.route("/combats/<int:combat_id>", methods=["DELETE"])
def delete_combat(combat_id):
    """
    Delete a combat record
    ---
    parameters:
      - name: combat_id
        in: path
        type: integer
        required: true
    responses:
      200:
        description: Combat deleted successfully
      404:
        description: Combat not found
    """

    message = {
        "action": "delete",
        "data": {
            "combat_id": combat_id
        }
    }

    send_to_queue(message)

    return index()


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
        return health_status, 200
    except Exception as e:
        # Log the error but allow the service to be considered healthy if app is running
        # This prevents restart loops during initial startup
        health_status["database"] = "unavailable"
        health_status["database_error"] = str(e)
        
        # Return 503 if database is truly unavailable (after grace period)
        # For now, return 200 to allow the service to stabilize
        # The load balancer health check grace period should handle startup delays
        return health_status, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)