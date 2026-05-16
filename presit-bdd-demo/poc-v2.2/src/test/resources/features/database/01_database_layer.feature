# language: zh-TW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT Phase 1：數據庫層驗證 (v2.2)
# 對應 v2.2 §1.3 C1 已解：應用真連 Postgres，schema 由 Flyway 管。
# 三 schema 對應三個 microservice：
#   - customers_schema (owners, pets, types)
#   - vets_schema      (vets, specialties, vet_specialties)
#   - visits_schema    (visits)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@pre-sit @phase-1 @database
功能: Pre-SIT 數據庫層驗證

  背景:
    假設 PostgreSQL 容器已在 Kind 集群的 "pre-sit" 命名空間中運行
    並且 數據庫連線資訊如下:
      | 參數     | 值                  |
      | host     | postgres.pre-sit.svc |
      | port     | 5432                |
      | database | petclinic           |
      | username | petclinic           |
      | password | petclinic           |
    並且 Flyway 已執行完成

  # ─── DDL：表結構驗證 ─────────────────────────────
  @ddl @critical @smoke
  場景大綱: 核心業務表已正確建立於對應 schema
    當 我查詢 schema "<schema>" 的表清單
    那麼 表 "<schema>"."<table_name>" 應該存在
    並且 表 "<schema>"."<table_name>" 的欄位數量應為 <column_count>

    例子:
      | schema           | table_name      | column_count |
      | customers_schema | owners          | 6            |
      | customers_schema | pets            | 5            |
      | customers_schema | types           | 2            |
      | vets_schema      | vets            | 3            |
      | vets_schema      | specialties     | 2            |
      | vets_schema      | vet_specialties | 2            |
      | visits_schema    | visits          | 4            |

  @ddl @columns
  場景: customers_schema.owners 表欄位定義正確（v2.2 含 city 欄位）
    當 我查詢 schema "customers_schema" 表 "owners" 的欄位定義
    那麼 欄位定義應完全符合:
      | column_name | data_type         | is_nullable | max_length |
      | id          | integer           | NO          |            |
      | first_name  | character varying | YES         | 30         |
      | last_name   | character varying | YES         | 30         |
      | address     | character varying | YES         | 255        |
      | city        | character varying | YES         | 80         |
      | telephone   | character varying | YES         | 20         |

  @ddl @columns
  場景: customers_schema.pets 表欄位定義正確
    當 我查詢 schema "customers_schema" 表 "pets" 的欄位定義
    那麼 欄位定義應完全符合:
      | column_name | data_type         | is_nullable | max_length |
      | id          | integer           | NO          |            |
      | name        | character varying | YES         | 30         |
      | birth_date  | date              | YES         |            |
      | type_id     | integer           | NO          |            |
      | owner_id    | integer           | NO          |            |

  # ─── DDL：約束驗證 ──────────────────────────────
  @ddl @constraints @primary-key
  場景: 所有業務表的主鍵約束正確
    當 我查詢所有 schema 表的主鍵約束
    那麼 以下主鍵應存在:
      | schema           | table_name  | pk_column |
      | customers_schema | owners      | id        |
      | customers_schema | pets        | id        |
      | customers_schema | types       | id        |
      | vets_schema      | vets        | id        |
      | vets_schema      | specialties | id        |
      | visits_schema    | visits      | id        |

  @ddl @constraints @foreign-key
  場景: 同 schema 內外鍵關係正確建立
    當 我查詢所有 schema 內的外鍵約束
    那麼 以下外鍵關係應存在:
      | schema           | child_table     | child_column   | parent_table | parent_column |
      | customers_schema | pets            | owner_id       | owners       | id            |
      | customers_schema | pets            | type_id        | types        | id            |
      | vets_schema      | vet_specialties | vet_id         | vets         | id            |
      | vets_schema      | vet_specialties | specialty_id   | specialties  | id            |
    # 注意: visits.pet_id → pets.id 是跨 schema 邏輯關係，
    # v2.2 §6 決策不設物理 FK (避免 DDL coupling)，改在應用層 + 下一場景驗證

  @ddl @indexes
  場景: 查詢效能索引已建立
    當 我查詢所有使用者定義的索引
    那麼 以下索引應存在:
      | schema           | table_name | index_name        |
      | customers_schema | owners     | owners_last_name  |
      | customers_schema | pets       | pets_name         |
      | vets_schema      | vets       | vets_last_name    |

  # ─── Flyway 歷史紀錄驗證 (v2.2 新增) ──────────
  @ddl @flyway
  場景大綱: 各 schema 之 Flyway migration 歷史完整
    當 我查詢 schema "<schema>".flyway_schema_history
    那麼 應至少有 <min_versions> 個成功 migration
    並且 最後一個 version 應為 "<last_version>"

    例子:
      | schema           | min_versions | last_version |
      | customers_schema | 2            | 2            |
      | vets_schema      | 2            | 2            |
      | visits_schema    | 2            | 2            |

  # ─── DML：測試數據驗證 ─────────────────────────
  @dml @data-loading @smoke
  場景: 測試數據筆數符合預期
    當 我統計各 schema 各表的資料筆數
    那麼 各表資料筆數不低於:
      | schema           | table_name      | min_count |
      | customers_schema | owners          | 10        |
      | customers_schema | pets            | 13        |
      | customers_schema | types           | 6         |
      | vets_schema      | vets            | 6         |
      | vets_schema      | specialties     | 3         |
      | vets_schema      | vet_specialties | 5         |
      | visits_schema    | visits          | 4         |

  @dml @referential-integrity
  場景: customers_schema 內 pets.owner_id 全部指向有效的 owners 記錄
    當 我執行引用完整性檢查 SQL:
      """
      SELECT p.id, p.name, p.owner_id
      FROM customers_schema.pets p
      LEFT JOIN customers_schema.owners o ON p.owner_id = o.id
      WHERE o.id IS NULL
      """
    那麼 查詢結果應為空集合

  @dml @referential-integrity @cross-schema
  場景: 跨 schema 引用完整性 - visits.pet_id 全部指向有效的 pets 記錄
    當 我執行引用完整性檢查 SQL:
      """
      SELECT v.id, v.pet_id
      FROM visits_schema.visits v
      LEFT JOIN customers_schema.pets p ON v.pet_id = p.id
      WHERE p.id IS NULL
      """
    那麼 查詢結果應為空集合

  @dml @sample-data
  場景: 標準測試數據內容正確 (含 v2.2 新增 city)
    當 我查詢 customers_schema.owners 表中 first_name 為 "George" 的記錄
    那麼 應返回 1 筆記錄
    並且 該記錄的欄位值為:
      | field      | value              |
      | last_name  | Franklin           |
      | address    | 110 W. Liberty St. |
      | city       | Madison            |
      | telephone  | 6085551023         |

  # ─── 序列與自增驗證 ────────────────────────────
  @ddl @sequences
  場景: 自增序列正常運作
    當 我對 customers_schema.owners 表插入一筆測試記錄:
      | first_name | last_name | address    | city    | telephone  |
      | Test       | User      | 123 St.    | Taipei  | 0912345678 |
    那麼 插入應成功
    並且 返回的 id 應大於 0
    當 我刪除該筆測試記錄
    那麼 刪除應成功
