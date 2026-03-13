CREATE TABLE combats (
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
