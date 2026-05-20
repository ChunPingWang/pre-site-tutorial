-- customers-service schema: owners / pets / types
-- 對應 PetClinic customers-service Flyway V1 migration

CREATE TABLE IF NOT EXISTS owners (
    id         SERIAL PRIMARY KEY,
    first_name VARCHAR(30),
    last_name  VARCHAR(30),
    address    VARCHAR(255),
    city       VARCHAR(80),
    telephone  VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS types (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(80)
);

CREATE TABLE IF NOT EXISTS pets (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(30),
    birth_date DATE,
    type_id    INTEGER NOT NULL REFERENCES customers_schema.types(id),
    owner_id   INTEGER NOT NULL REFERENCES customers_schema.owners(id)
);

CREATE INDEX IF NOT EXISTS owners_last_name ON owners (last_name);
CREATE INDEX IF NOT EXISTS pets_name        ON pets (name);
