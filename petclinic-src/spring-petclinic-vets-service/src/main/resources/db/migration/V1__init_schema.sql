-- vets-service Flyway migration V1
-- Schema=vets_schema (見 application.yml flyway.schemas)

CREATE TABLE vets (
  id         SERIAL PRIMARY KEY,
  first_name VARCHAR(30),
  last_name  VARCHAR(30)
);
CREATE INDEX vets_last_name ON vets (last_name);

CREATE TABLE specialties (
  id   SERIAL PRIMARY KEY,
  name VARCHAR(80)
);
CREATE INDEX specialties_name ON specialties (name);

CREATE TABLE vet_specialties (
  vet_id       INTEGER NOT NULL REFERENCES vets (id),
  specialty_id INTEGER NOT NULL REFERENCES specialties (id),
  PRIMARY KEY (vet_id, specialty_id)
);
