-- vets-service schema: vets / specialties / vet_specialties
-- 對應 PetClinic vets-service Flyway V1 migration

CREATE TABLE IF NOT EXISTS vets (
    id         SERIAL PRIMARY KEY,
    first_name VARCHAR(30),
    last_name  VARCHAR(30)
);

CREATE TABLE IF NOT EXISTS specialties (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(80)
);

CREATE TABLE IF NOT EXISTS vet_specialties (
    vet_id       INTEGER NOT NULL REFERENCES vets_schema.vets(id),
    specialty_id INTEGER NOT NULL REFERENCES vets_schema.specialties(id),
    PRIMARY KEY (vet_id, specialty_id)
);

CREATE INDEX IF NOT EXISTS vets_last_name ON vets (last_name);
