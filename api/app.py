from flask import Flask, render_template, request
import pika
import json
import psycopg2

app = Flask(__name__)


def get_db():
    return psycopg2.connect(
        host="db",
        database="combats",
        user="admin",
        password="admin"
    )


def send_to_queue(message):

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host="rabbitmq")
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

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT * FROM combats ORDER BY id DESC")
    combats = cur.fetchall()

    cur.close()
    conn.close()

    return render_template("index.html", combats=combats)


@app.route("/combats", methods=["POST"])
def create_combat():

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
