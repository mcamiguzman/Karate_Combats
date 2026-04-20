-- Combats Table: Stores karate combat records
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
    status VARCHAR(20) DEFAULT 'pending',
    date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Orders Table: Tracks consumer transactions and actions on combats
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    combat_id INT NOT NULL REFERENCES combats(id) ON DELETE CASCADE,
    consumer_id VARCHAR(100),
    action VARCHAR(50) NOT NULL,
    action_details JSONB,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

-- Create indexes for improved query performance
CREATE INDEX idx_combats_status ON combats(status);
CREATE INDEX idx_combats_date ON combats(date);
CREATE INDEX idx_orders_combat_id ON orders(combat_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at);
