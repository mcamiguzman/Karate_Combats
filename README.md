# KARATE COMBATS SYSTEM

## General Information

**Project:** Karate Combats Management System  
**Course:** Internet of Things  
**Professor:** Carlos Alberto Llano Rodriguez  

**Team Members:**
- Maria Camila Guzman Bolaños  
- Mateo Ramirez Gutierrez  

---

## Project Description

This project consists of the development of a distributed system for registering and managing karate combats. The application allows users to register combats through a web interface, process them asynchronously using a message queue, and store them in a relational database.

The system implements a microservices-based architecture, which enables decoupling between components and improves scalability and maintainability.

---

## System Architecture

The system is composed of the following services:

- **API:** Implemented with Flask, it handles HTTP requests from the web interface.
- **RabbitMQ:** Messaging system that enables asynchronous communication between services.
- **Worker:** Consumer service that processes messages and inserts data into the database.
- **Database:** PostgreSQL, where combat records are stored.

---

**Workflow:**

Browser → API → RabbitMQ → Worker → PostgreSQL


---

## Technologies Used

- Python 3  
- Flask  
- RabbitMQ  
- PostgreSQL  
- Docker  
- Docker Compose  
- HTML and CSS  

---

## Project Structure

- karatecombats/
  - docker-compose.yml
  - api/
    - Dockerfile
    - app.py
    - templates/
      - index.html
  - worker/
    - Dockerfile
    - worker.py
  - db/
    - init.sql


---

## Execution Instructions

### Requirements

- Docker installed  
- Docker Compose installed  

### Steps to Run

1. Clone the repository:

git clone <REPOSITORY_URL>
cd karatecombats

docker compose up --build


3. Access the application:

- Web interface:  
  http://localhost:5000  

- RabbitMQ dashboard:  
  http://localhost:15672  

  Username: guest  
  Password: guest  

---

## System Operation

1. The user enters combat data through the web interface.  
2. The API receives the request and sends a message to RabbitMQ.  
3. The Worker consumes the message from the queue.  
4. The Worker processes the data and inserts it into PostgreSQL.  
5. The web interface displays the list of registered combats.  

---

## Database

The database contains a table named `combats` with the following fields:

- id  
- time  
- participant_red  
- participant_blue  
- points_red  
- points_blue  
- fouls_red  
- fouls_blue  
- judges  
- status  

---

## Useful Commands

View running containers:

docker ps


View logs:


docker logs -f karatecombats-api-1
docker logs -f karatecombats-worker-1
docker logs -f karatecombats-db-1


Access the database:


docker exec -it karatecombats-db-1 psql -U admin -d combats


Query data:


SELECT * FROM combats;


---

## Common Issues

### Worker not running

- Ensure RabbitMQ is fully initialized.  
- Check worker container logs.  

### Data not appearing in the database

- Verify that the worker is processing messages.  
- Check database connection.  
- Ensure the table exists.  

---

## Conclusions

This project allowed the application of distributed system concepts, asynchronous communication using message queues, and containerized application deployment with Docker. It also highlights the importance of service decoupling to improve system scalability and maintainability.
