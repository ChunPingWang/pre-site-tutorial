# language: zh-TW
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT Phase 1：數據庫層驗證
# 對應工作計劃：第二階段 — 數據庫層設計與實現
# 驗證項目：DDL 執行 → DML 載入 → 約束與索引 → 數據完整性
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@pre-sit @phase-1 @database
功能: Pre-SIT 數據庫層驗證
  作為 數據架構師
  我希望 在應用部署前驗證容器化 PostgreSQL 的 Schema 與數據
  以便 確保 DDL 與 DML 腳本可在任何環境正確重現

  背景:
    假設 PostgreSQL 容器已在 Kind 集群的 "pre-sit" 命名空間中運行
    並且 數據庫連線資訊如下:
      | 參數     | 值                           |
      | host     | postgres-service.pre-sit.svc |
      | port     | 5432                         |
      | database | petclinic                    |
      | username | postgres                     |
      | password | postgres                     |
    並且 InitContainer 已執行完成

  # ─── DDL：表結構驗證 ─────────────────────────────
  @ddl @critical @smoke
  場景大綱: 核心業務表已正確建立
    當 我查詢 information_schema.tables 中 schema "public" 的表清單
    那麼 表 "<table_name>" 應該存在
    並且 表 "<table_name>" 的欄位數量應為 <column_count>

    例子:
      | table_name      | column_count |
      | owners          | 5            |
      | pets            | 5            |
      | types           | 2            |
      | vets            | 3            |
      | specialties     | 2            |
      | vet_specialties | 2            |
      | visits          | 4            |

  @ddl @columns
  場景: owners 表欄位定義正確
    當 我查詢表 "owners" 的欄位定義
    那麼 欄位定義應完全符合:
      | column_name | data_type         | is_nullable | max_length |
      | id          | integer           | NO          |            |
      | first_name  | character varying | YES         | 30         |
      | last_name   | character varying | YES         | 30         |
      | address     | character varying | YES         | 255        |
      | telephone   | character varying | YES         | 20         |

  @ddl @columns
  場景: pets 表欄位定義正確
    當 我查詢表 "pets" 的欄位定義
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
    當 我查詢所有表的主鍵約束
    那麼 以下主鍵應存在:
      | table_name      | pk_column |
      | owners          | id        |
      | pets            | id        |
      | types           | id        |
      | vets            | id        |
      | specialties     | id        |
      | visits          | id        |

  @ddl @constraints @foreign-key
  場景: 外鍵關係正確建立
    當 我查詢所有外鍵約束
    那麼 以下外鍵關係應存在:
      | child_table     | child_column   | parent_table | parent_column |
      | pets            | owner_id       | owners       | id            |
      | pets            | type_id        | types        | id            |
      | visits          | pet_id         | pets         | id            |
      | vet_specialties | vet_id         | vets         | id            |
      | vet_specialties | specialty_id   | specialties  | id            |

  @ddl @indexes
  場景: 查詢效能索引已建立
    當 我查詢所有使用者定義的索引
    那麼 以下索引應存在:
      | table_name | index_name            |
      | owners     | idx_owners_last_name  |
      | pets       | idx_pets_name         |
      | vets       | idx_vets_last_name    |

  # ─── DML：測試數據驗證 ─────────────────────────
  @dml @data-loading @smoke
  場景: 測試數據筆數符合預期
    當 我統計各表的資料筆數
    那麼 各表資料筆數不低於:
      | table_name      | min_count |
      | owners          | 10        |
      | pets            | 13        |
      | types           | 6         |
      | vets            | 6         |
      | specialties     | 3         |
      | vet_specialties | 5         |
      | visits          | 4         |

  @dml @referential-integrity
  場景: pets 的 owner_id 全部指向有效的 owners 記錄
    當 我執行引用完整性檢查 SQL:
      """
      SELECT p.id, p.name, p.owner_id
      FROM pets p
      LEFT JOIN owners o ON p.owner_id = o.id
      WHERE o.id IS NULL
      """
    那麼 查詢結果應為空集合
    因為 不應存在孤立的寵物記錄

  @dml @referential-integrity
  場景: visits 的 pet_id 全部指向有效的 pets 記錄
    當 我執行引用完整性檢查 SQL:
      """
      SELECT v.id, v.pet_id
      FROM visits v
      LEFT JOIN pets p ON v.pet_id = p.id
      WHERE p.id IS NULL
      """
    那麼 查詢結果應為空集合
    因為 不應存在找不到寵物的就診記錄

  @dml @sample-data
  場景: 標準測試數據內容正確
    當 我查詢 owners 表中 first_name 為 "George" 的記錄
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
    當 我對 owners 表插入一筆測試記錄:
      | first_name | last_name | address    | city    | telephone  |
      | Test       | User      | 123 St.    | Taipei  | 0912345678 |
    那麼 插入應成功
    並且 返回的 id 應大於 0
    當 我刪除該筆測試記錄
    那麼 刪除應成功
