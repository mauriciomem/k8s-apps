-- Runs once, the first time the database starts with an empty data directory.
CREATE TABLE IF NOT EXISTS items (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

INSERT INTO items (name) VALUES
    ('first item'),
    ('second item'),
    ('third item');
