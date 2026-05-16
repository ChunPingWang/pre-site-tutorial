-- visits-service Flyway migration V1
-- Schema=visits_schema (見 application.yml flyway.schemas)
--
-- 注意：visits.pet_id 在邏輯上 reference 到 customers_schema.pets.id，
-- 但因 microservices 跨 schema 不設 FK（避免 DDL coupling），
-- 引用完整性改在應用層 / Phase 1 BDD 跨 schema query 驗證。

-- visit_date 對應 entity 的 @Temporal(TIMESTAMP) Date → 用 TIMESTAMP 而非 DATE
-- （upstream HSQLDB 用 DATE 仍能跑是因 HSQLDB schema validation 較鬆；
--   Hibernate 對 PG 6 嚴格驗證型別）
CREATE TABLE visits (
  id          SERIAL PRIMARY KEY,
  pet_id      INTEGER NOT NULL,
  visit_date  TIMESTAMP,
  description VARCHAR(8192)
);
CREATE INDEX visits_pet_id ON visits (pet_id);
