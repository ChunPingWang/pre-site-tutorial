-- visits-service schema: visits
-- pet_id 不設物理 FK（跨 schema，避免 DDL coupling；應用層驗證）

CREATE TABLE IF NOT EXISTS visits (
    id          SERIAL PRIMARY KEY,
    pet_id      INTEGER NOT NULL,
    visit_date  DATE,
    description VARCHAR(8192)
);
