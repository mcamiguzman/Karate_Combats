import pika
import json
import psycopg2
import time


def wait_for_rabbitmq():
    while True:
        try:
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(host="rabbitmq")
            )
            print("Connected to RabbitMQ")
            return connection
        except pika.exceptions.AMQPConnectionError:
            print("RabbitMQ not ready, retrying in 5 seconds...")
            time.sleep(5)


def get_db():
    while True:
        try:
            conn = psycopg2.connect(
                host="db",
                database="combats",
                user="admin",
                password="admin"
            )
            print("Connected to PostgreSQL")
            return conn
        except psycopg2.OperationalError:
            print("PostgreSQL not ready, retrying in 5 seconds...")
            time.sleep(5)


def callback(ch, method, properties, body):

    print("Message received")

    message = json.loads(body)

    if message["action"] == "create":

        data = message["data"]

        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
        INSERT INTO combats
        (time, participant_red, participant_blue,
        points_red, points_blue, fouls_red, fouls_blue, judges, status)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'created')
        """, (
            data["time"],
            data["red"],
            data["blue"],
            data["points_red"],
            data["points_blue"],
            data["fouls_red"],
            data["fouls_blue"],
            data["judges"]
        ))

        conn.commit()

        cur.close()
        conn.close()

        print("Combat stored in database")

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
