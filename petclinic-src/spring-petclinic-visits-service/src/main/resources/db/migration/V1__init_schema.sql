-- visits-service Flyway migration V1
-- Schema=visits_schema (見 application.yml flyway.schemas)
--
-- 注意：visits.pet_id 在邏輯上 reference 到 customers_schema.pets.id，
-- 但因 microservices 跨 schema 不設 FK（避免 DDL coupling），
-- 引用完整性改在應用層 / Phase 1 BDD 跨 schema query 驗證。

CREATE TABLE visits (
  id          SERIAL PRIMARY KEY,
  pet_id      INTEGER NOT NULL,
  visit_date  DATE,
  description VARCHAR(8192)
);
CREATE INDEX visits_pet_id ON visits (pet_id);
