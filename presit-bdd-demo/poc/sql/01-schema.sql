-- Pre-SIT PetClinic schema. Column counts/types/FKs/indexes here are load-bearing:
-- they are asserted verbatim by features/database/01_database_layer.feature.

CREATE TABLE owners (
    id          SERIAL PRIMARY KEY,
    first_name  VARCHAR(30),
    last_name   VARCHAR(30),
    address     VARCHAR(255),
    telephone   VARCHAR(20)
);

CREATE TABLE types (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(80)
);

CREATE TABLE pets (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(30),
    birth_date DATE,
    type_id    INTEGER NOT NULL REFERENCES types(id),
    owner_id   INTEGER NOT NULL REFERENCES owners(id)
);

CREATE TABLE visits (
    id          SERIAL PRIMARY KEY,
    pet_id      INTEGER NOT NULL REFERENCES pets(id),
    visit_date  DATE,
    description VARCHAR(8192)
);

CREATE TABLE vets (
    id         SERIAL PRIMARY KEY,
    first_name VARCHAR(30),
    last_name  VARCHAR(30)
);

CREATE TABLE specialties (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(80)
);

CREATE TABLE vet_specialties (
    vet_id       INTEGER NOT NULL REFERENCES vets(id),
    specialty_id INTEGER NOT NULL REFERENCES specialties(id),
    PRIMARY KEY (vet_id, specialty_id)
);

CREATE INDEX idx_owners_last_name ON owners (last_name);
CREATE INDEX idx_pets_name        ON pets (name);
CREATE INDEX idx_vets_last_name   ON vets (last_name);
