-- customers-service Flyway migration V1
-- 對應 upstream HSQLDB schema (v3.2.0)，移植到 PostgreSQL。
-- Schema 切割於 application.yml flyway.schemas=customers_schema 指定。

CREATE TABLE types (
  id   SERIAL PRIMARY KEY,
  name VARCHAR(80)
);
CREATE INDEX types_name ON types (name);

CREATE TABLE owners (
  id         SERIAL PRIMARY KEY,
  first_name VARCHAR(30),
  last_name  VARCHAR(30),
  address    VARCHAR(255),
  city       VARCHAR(80),
  telephone  VARCHAR(20)
);
CREATE INDEX owners_last_name ON owners (last_name);

CREATE TABLE pets (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(30),
  birth_date DATE,
  type_id    INTEGER NOT NULL REFERENCES types (id),
  owner_id   INTEGER NOT NULL REFERENCES owners (id)
);
CREATE INDEX pets_name ON pets (name);
