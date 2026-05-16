package com.presit.steps;

import io.cucumber.datatable.DataTable;
import io.cucumber.java.After;
import io.cucumber.java.Before;
import io.cucumber.java.zh_tw.*;

import java.sql.*;
import java.util.*;

import static org.assertj.core.api.Assertions.*;

/**
 * v2.2 BDD Phase 1 step definitions — 支援 schema-qualified queries
 * 適配 customers_schema / vets_schema / visits_schema 三 schema 結構
 */
public class DatabaseLayerSteps {

    private Connection connection;
    private String currentSchema;
    private String currentTable;
    private final List<Map<String, String>> lastRows = new ArrayList<>();
    private int lastInsertedId = -1;

    private final String dbHost     = System.getenv().getOrDefault("DB_HOST",     "localhost");
    private final String dbPort     = System.getenv().getOrDefault("DB_PORT",     "5432");
    private final String dbName     = System.getenv().getOrDefault("DB_NAME",     "petclinic");
    private final String dbUser     = System.getenv().getOrDefault("DB_USER",     "petclinic");
    private final String dbPassword = System.getenv().getOrDefault("DB_PASSWORD", "petclinic");

    @Before("@database")
    public void setupConnection() throws SQLException {
        String url = String.format("jdbc:postgresql://%s:%s/%s", dbHost, dbPort, dbName);
        connection = DriverManager.getConnection(url, dbUser, dbPassword);
        connection.setAutoCommit(true);
        System.out.printf("[Pre-SIT] DB 連線成功: %s%n", url);
    }

    @After("@database")
    public void teardownConnection() throws SQLException {
        if (connection != null && !connection.isClosed()) connection.close();
    }

    // ─── Background steps ─────────────────────────────────────
    @假設("PostgreSQL 容器已在 Kind 集群的 {string} 命名空間中運行")
    public void verifyPostgresRunning(String ns) {
        assertThat(connection).isNotNull();
    }

    @假設("數據庫連線資訊如下:")
    public void dbConnectionInfo(DataTable t) { /* informational */ }

    @假設("Flyway 已執行完成")
    public void flywayCompleted() throws SQLException {
        for (String s : new String[]{"customers_schema","vets_schema","visits_schema"}) {
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery(
                     "SELECT count(*) FROM " + s + ".flyway_schema_history WHERE success=true")) {
                rs.next();
                assertThat(rs.getInt(1)).as("%s 應至少有 1 個 Flyway migration", s).isGreaterThanOrEqualTo(1);
            }
        }
    }

    @當("我查詢 schema {string} 的表清單")
    public void querySchemaTables(String schema) { currentSchema = schema; }

    @那麼("表 {string}.{string} 應該存在")
    public void tableShouldExist(String schema, String table) throws SQLException {
        currentSchema = schema; currentTable = table;
        try (PreparedStatement ps = connection.prepareStatement(
                "SELECT count(*) FROM information_schema.tables WHERE table_schema=? AND table_name=?")) {
            ps.setString(1, schema); ps.setString(2, table);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                assertThat(rs.getInt(1)).as("表 %s.%s 應存在", schema, table).isEqualTo(1);
            }
        }
    }

    @那麼("表 {string}.{string} 的欄位數量應為 {int}")
    public void tableColumnCount(String schema, String table, int expected) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(
                "SELECT count(*) FROM information_schema.columns WHERE table_schema=? AND table_name=?")) {
            ps.setString(1, schema); ps.setString(2, table);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                assertThat(rs.getInt(1)).as("%s.%s 欄位數", schema, table).isEqualTo(expected);
            }
        }
    }

    @當("我查詢 schema {string} 表 {string} 的欄位定義")
    public void queryColumnDefinitions(String schema, String table) {
        currentSchema = schema; currentTable = table;
    }

    @那麼("欄位定義應完全符合:")
    public void columnsShouldMatch(DataTable expected) throws SQLException {
        for (Map<String, String> row : expected.asMaps()) {
            String col = row.get("column_name");
            try (PreparedStatement ps = connection.prepareStatement(
                    "SELECT data_type, is_nullable, character_maximum_length " +
                    "FROM information_schema.columns WHERE table_schema=? AND table_name=? AND column_name=?")) {
                ps.setString(1, currentSchema); ps.setString(2, currentTable); ps.setString(3, col);
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).as("欄位 %s.%s.%s 應存在", currentSchema, currentTable, col).isTrue();
                    assertThat(rs.getString("data_type"))
                            .as("欄位 %s data_type", col).isEqualTo(row.get("data_type"));
                    assertThat(rs.getString("is_nullable"))
                            .as("欄位 %s is_nullable", col).isEqualTo(row.get("is_nullable"));
                    String maxLen = row.get("max_length");
                    if (maxLen != null && !maxLen.isBlank()) {
                        assertThat(rs.getInt("character_maximum_length"))
                                .as("欄位 %s max_length", col).isEqualTo(Integer.parseInt(maxLen));
                    }
                }
            }
        }
    }

    @當("我查詢所有 schema 表的主鍵約束")
    public void queryAllPrimaryKeys() { }

    @那麼("以下主鍵應存在:")
    public void primaryKeysShouldExist(DataTable t) throws SQLException {
        String sql =
            "SELECT kcu.column_name FROM information_schema.table_constraints tc " +
            "JOIN information_schema.key_column_usage kcu " +
            "  ON tc.constraint_name=kcu.constraint_name AND tc.table_schema=kcu.table_schema " +
            "WHERE tc.table_schema=? AND tc.table_name=? AND tc.constraint_type='PRIMARY KEY' " +
            "ORDER BY kcu.ordinal_position";
        for (Map<String, String> row : t.asMaps()) {
            try (PreparedStatement ps = connection.prepareStatement(sql)) {
                ps.setString(1, row.get("schema")); ps.setString(2, row.get("table_name"));
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).as("%s.%s 應有主鍵", row.get("schema"), row.get("table_name")).isTrue();
                    assertThat(rs.getString("column_name")).as("%s.%s PK 欄位",
                            row.get("schema"), row.get("table_name")).isEqualTo(row.get("pk_column"));
                }
            }
        }
    }

    @當("我查詢所有 schema 內的外鍵約束")
    public void queryAllForeignKeys() { }

    @那麼("以下外鍵關係應存在:")
    public void foreignKeysShouldExist(DataTable t) throws SQLException {
        String sql =
            "SELECT ccu.table_name AS parent_table, ccu.column_name AS parent_column " +
            "FROM information_schema.table_constraints tc " +
            "JOIN information_schema.key_column_usage kcu " +
            "  ON tc.constraint_name=kcu.constraint_name AND tc.table_schema=kcu.table_schema " +
            "JOIN information_schema.constraint_column_usage ccu " +
            "  ON tc.constraint_name=ccu.constraint_name " +
            "WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema=? AND tc.table_name=? AND kcu.column_name=?";
        for (Map<String, String> row : t.asMaps()) {
            try (PreparedStatement ps = connection.prepareStatement(sql)) {
                ps.setString(1, row.get("schema"));
                ps.setString(2, row.get("child_table"));
                ps.setString(3, row.get("child_column"));
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).as("FK %s.%s.%s 應存在",
                            row.get("schema"), row.get("child_table"), row.get("child_column")).isTrue();
                    assertThat(rs.getString("parent_table")).isEqualTo(row.get("parent_table"));
                    assertThat(rs.getString("parent_column")).isEqualTo(row.get("parent_column"));
                }
            }
        }
    }

    @當("我查詢所有使用者定義的索引")
    public void queryUserIndexes() { }

    @那麼("以下索引應存在:")
    public void indexesShouldExist(DataTable t) throws SQLException {
        for (Map<String, String> row : t.asMaps()) {
            try (PreparedStatement ps = connection.prepareStatement(
                    "SELECT count(*) FROM pg_indexes WHERE schemaname=? AND tablename=? AND indexname=?")) {
                ps.setString(1, row.get("schema"));
                ps.setString(2, row.get("table_name"));
                ps.setString(3, row.get("index_name"));
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    assertThat(rs.getInt(1)).as("索引 %s.%s.%s 應存在",
                            row.get("schema"), row.get("table_name"), row.get("index_name")).isEqualTo(1);
                }
            }
        }
    }

    @當("我查詢 schema {string}.flyway_schema_history")
    public void queryFlywayHistory(String schema) throws SQLException {
        currentSchema = schema;
        lastRows.clear();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery(
                 "SELECT version, description, success FROM " + sanitizeSchema(schema) +
                 ".flyway_schema_history WHERE success=true ORDER BY installed_rank")) {
            while (rs.next()) {
                Map<String, String> r = new LinkedHashMap<>();
                r.put("version", rs.getString("version"));
                r.put("description", rs.getString("description"));
                r.put("success", String.valueOf(rs.getBoolean("success")));
                lastRows.add(r);
            }
        }
    }

    @那麼("應至少有 {int} 個成功 migration")
    public void shouldHaveAtLeastNMigrations(int n) {
        long versioned = lastRows.stream().filter(r -> r.get("version") != null).count();
        assertThat(versioned).as("%s 成功 migration 數", currentSchema).isGreaterThanOrEqualTo(n);
    }

    @那麼("最後一個 version 應為 {string}")
    public void lastVersionShouldBe(String expected) {
        String lastNonNull = null;
        for (Map<String, String> r : lastRows) {
            if (r.get("version") != null) lastNonNull = r.get("version");
        }
        assertThat(lastNonNull).as("%s 最後 version", currentSchema).isEqualTo(expected);
    }

    @當("我統計各 schema 各表的資料筆數")
    public void countAllRows() { }

    @那麼("各表資料筆數不低於:")
    public void rowCountsShouldMeetMinimum(DataTable t) throws SQLException {
        for (Map<String, String> row : t.asMaps()) {
            String full = sanitizeSchema(row.get("schema")) + "." + sanitizeIdent(row.get("table_name"));
            int min = Integer.parseInt(row.get("min_count"));
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery("SELECT count(*) FROM " + full)) {
                rs.next();
                int actual = rs.getInt(1);
                assertThat(actual).as("%s 至少 %d 筆", full, min).isGreaterThanOrEqualTo(min);
            }
        }
    }

    @當("我執行引用完整性檢查 SQL:")
    public void executeIntegrityCheck(String sql) throws SQLException {
        lastRows.clear();
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            ResultSetMetaData md = rs.getMetaData();
            int cols = md.getColumnCount();
            while (rs.next()) {
                Map<String, String> r = new LinkedHashMap<>();
                for (int i = 1; i <= cols; i++) r.put(md.getColumnLabel(i), rs.getString(i));
                lastRows.add(r);
            }
        }
    }

    @那麼("查詢結果應為空集合")
    public void resultShouldBeEmpty() {
        assertThat(lastRows).as("應無孤立記錄").isEmpty();
    }

    @當("我查詢 customers_schema.owners 表中 first_name 為 {string} 的記錄")
    public void queryOwnerByFirstName(String firstName) throws SQLException {
        lastRows.clear();
        try (PreparedStatement ps = connection.prepareStatement(
                "SELECT * FROM customers_schema.owners WHERE first_name = ?")) {
            ps.setString(1, firstName);
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData md = rs.getMetaData();
                int cols = md.getColumnCount();
                while (rs.next()) {
                    Map<String, String> r = new LinkedHashMap<>();
                    for (int i = 1; i <= cols; i++) r.put(md.getColumnLabel(i), rs.getString(i));
                    lastRows.add(r);
                }
            }
        }
    }

    @那麼("應返回 {int} 筆記錄")
    public void shouldReturnNRecords(int expected) { assertThat(lastRows).as("回傳筆數").hasSize(expected); }

    @那麼("該記錄的欄位值為:")
    public void recordFieldsShouldMatch(DataTable t) {
        assertThat(lastRows).as("需要至少一筆記錄").isNotEmpty();
        Map<String, String> row = lastRows.get(0);
        for (Map<String, String> kv : t.asMaps()) {
            String field = kv.get("field"); String want = kv.get("value");
            assertThat(row).as("該記錄應含欄位 '%s'", field).containsKey(field);
            assertThat(row.get(field)).as("欄位 '%s'", field).isEqualTo(want);
        }
    }

    @當("我對 customers_schema.owners 表插入一筆測試記錄:")
    public void insertTestOwner(DataTable t) throws SQLException {
        Map<String, String> d = t.asMaps().get(0);
        try (PreparedStatement ps = connection.prepareStatement(
                "INSERT INTO customers_schema.owners (first_name, last_name, address, city, telephone) " +
                "VALUES (?, ?, ?, ?, ?) RETURNING id")) {
            ps.setString(1, d.get("first_name"));
            ps.setString(2, d.get("last_name"));
            ps.setString(3, d.get("address"));
            ps.setString(4, d.get("city"));
            ps.setString(5, d.get("telephone"));
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                lastInsertedId = rs.getInt("id");
            }
        }
    }

    @那麼("插入應成功")
    public void insertShouldSucceed() { assertThat(lastInsertedId).isGreaterThan(0); }

    @那麼("返回的 id 應大於 {int}")
    public void idShouldBeGreaterThan(int v) { assertThat(lastInsertedId).isGreaterThan(v); }

    @當("我刪除該筆測試記錄")
    public void deleteTestRecord() throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(
                "DELETE FROM customers_schema.owners WHERE id = ?")) {
            ps.setInt(1, lastInsertedId);
            int n = ps.executeUpdate();
            assertThat(n).as("應刪除一筆").isEqualTo(1);
        }
    }

    @那麼("刪除應成功")
    public void deleteShouldSucceed() { }

    private String sanitizeSchema(String s) {
        if (!s.matches("^[a-zA-Z_][a-zA-Z0-9_]*$"))
            throw new IllegalArgumentException("Invalid schema name: " + s);
        return s;
    }
    private String sanitizeIdent(String s) {
        if (!s.matches("^[a-zA-Z_][a-zA-Z0-9_]*$"))
            throw new IllegalArgumentException("Invalid identifier: " + s);
        return s;
    }
}
