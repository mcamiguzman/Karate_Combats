from flask import Flask, render_template, request
import pika
import json
import psycopg2
import os
from flasgger import Swagger

app = Flask(__name__)
swagger = Swagger(app)

# Environment variables with defaults for local development
DB_HOST = os.environ.get("DB_HOST", "db")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "admin")
DB_NAME = os.environ.get("DB_NAME", "combats")

RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.environ.get("RABBITMQ_PORT", "5672"))


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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)