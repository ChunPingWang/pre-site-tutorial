package com.presit.steps;

import io.cucumber.datatable.DataTable;
import io.cucumber.java.After;
import io.cucumber.java.Before;
import io.cucumber.java.zh_tw.*;

import java.sql.*;
import java.util.*;

import static org.assertj.core.api.Assertions.*;

public class DatabaseLayerSteps {

    private Connection connection;
    private String currentTableName;
    private List<String> lastQueryColumnOrder = new ArrayList<>();
    private List<Map<String, String>> lastRows = new ArrayList<>();
    private int lastInsertedId = -1;

    private final String dbHost     = System.getenv().getOrDefault("DB_HOST", "localhost");
    private final String dbPort     = System.getenv().getOrDefault("DB_PORT", "5432");
    private final String dbName     = System.getenv().getOrDefault("DB_NAME", "petclinic");
    private final String dbUser     = System.getenv().getOrDefault("DB_USER", "postgres");
    private final String dbPassword = System.getenv().getOrDefault("DB_PASSWORD", "postgres");

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

    @假設("PostgreSQL 容器已在 Kind 集群的 {string} 命名空間中運行")
    public void verifyPostgresRunning(String namespace) {
        assertThat(connection).isNotNull();
    }

    @假設("數據庫連線資訊如下:")
    public void dbConnectionInfo(DataTable table) { /* informational */ }

    @假設("InitContainer 已執行完成")
    public void initContainerCompleted() throws SQLException {
        try (Statement st = connection.createStatement();
             ResultSet rs = st.executeQuery(
                 "SELECT count(*) FROM information_schema.tables " +
                 "WHERE table_schema='public' AND table_type='BASE TABLE'")) {
            rs.next();
            assertThat(rs.getInt(1)).as("InitContainer 應已建立表").isGreaterThan(0);
        }
    }

    @當("我查詢 information_schema.tables 中 schema {string} 的表清單")
    public void queryTablesInSchema(String schema) { /* trigger; check in @那麼 */ }

    @那麼("表 {string} 應該存在")
    public void tableShouldExist(String tableName) throws SQLException {
        currentTableName = tableName;
        try (PreparedStatement ps = connection.prepareStatement(
                "SELECT count(*) FROM information_schema.tables " +
                "WHERE table_schema='public' AND table_name=?")) {
            ps.setString(1, tableName);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                assertThat(rs.getInt(1)).as("表 '%s' 應存在", tableName).isEqualTo(1);
            }
        }
    }

    @那麼("表 {string} 的欄位數量應為 {int}")
    public void tableColumnCount(String tableName, int expected) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(
                "SELECT count(*) FROM information_schema.columns " +
                "WHERE table_schema='public' AND table_name=?")) {
            ps.setString(1, tableName);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                assertThat(rs.getInt(1)).as("表 '%s' 欄位數", tableName).isEqualTo(expected);
            }
        }
    }

    @當("我查詢表 {string} 的欄位定義")
    public void queryColumnDefinitions(String tableName) {
        currentTableName = tableName;
    }

    @那麼("欄位定義應完全符合:")
    public void columnsShouldMatch(DataTable expected) throws SQLException {
        for (Map<String, String> row : expected.asMaps()) {
            String col = row.get("column_name");
            try (PreparedStatement ps = connection.prepareStatement(
                    "SELECT data_type, is_nullable, character_maximum_length " +
                    "FROM information_schema.columns " +
                    "WHERE table_schema='public' AND table_name=? AND column_name=?")) {
                ps.setString(1, currentTableName);
                ps.setString(2, col);
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).as("欄位 '%s' 應存在於 '%s'", col, currentTableName).isTrue();
                    assertThat(rs.getString("data_type"))
                            .as("欄位 '%s' data_type", col).isEqualTo(row.get("data_type"));
                    assertThat(rs.getString("is_nullable"))
                            .as("欄位 '%s' is_nullable", col).isEqualTo(row.get("is_nullable"));
                    String maxLen = row.get("max_length");
                    if (maxLen != null && !maxLen.isBlank()) {
                        assertThat(rs.getInt("character_maximum_length"))
                                .as("欄位 '%s' max_length", col).isEqualTo(Integer.parseInt(maxLen));
                    }
                }
            }
        }
    }

    @當("我查詢所有表的主鍵約束")
    public void queryPrimaryKeys() { }

    @那麼("以下主鍵應存在:")
    public void primaryKeysShouldExist(DataTable table) throws SQLException {
        String sql =
            "SELECT kcu.column_name " +
            "FROM information_schema.table_constraints tc " +
            "JOIN information_schema.key_column_usage kcu " +
            "  ON tc.constraint_name = kcu.constraint_name " +
            "WHERE tc.table_schema='public' AND tc.constraint_type='PRIMARY KEY' " +
            "AND tc.table_name=? ORDER BY kcu.ordinal_position";
        for (Map<String, String> row : table.asMaps()) {
            try (PreparedStatement ps = connection.prepareStatement(sql)) {
                ps.setString(1, row.get("table_name"));
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).as("表 '%s' 應有主鍵", row.get("table_name")).isTrue();
                    assertThat(rs.getString("column_name"))
                        .as("表 '%s' 主鍵欄位", row.get("table_name"))
                        .isEqualTo(row.get("pk_column"));
                }
            }
        }
    }

    @當("我查詢所有外鍵約束")
    public void queryForeignKeys() { }

    @那麼("以下外鍵關係應存在:")
    public void foreignKeysShouldExist(DataTable table) throws SQLException {
        String sql =
            "SELECT ccu.table_name AS parent_table, ccu.column_name AS parent_column " +
            "FROM information_schema.table_constraints tc " +
            "JOIN information_schema.key_column_usage kcu " +
            "  ON tc.constraint_name = kcu.constraint_name " +
            "JOIN information_schema.constraint_column_usage ccu " +
            "  ON tc.constraint_name = ccu.constraint_name " +
            "WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_name=? AND kcu.column_name=?";
        for (Map<String, String> row : table.asMaps()) {
            try (PreparedStatement ps = connection.prepareStatement(sql)) {
                ps.setString(1, row.get("child_table"));
                ps.setString(2, row.get("child_column"));
                try (ResultSet rs = ps.executeQuery()) {
                    assertThat(rs.next()).as("FK %s.%s 應存在",
                            row.get("child_table"), row.get("child_column")).isTrue();
                    assertThat(rs.getString("parent_table")).isEqualTo(row.get("parent_table"));
                    assertThat(rs.getString("parent_column")).isEqualTo(row.get("parent_column"));
                }
            }
        }
    }

    @當("我查詢所有使用者定義的索引")
    public void queryUserIndexes() { }

    @那麼("以下索引應存在:")
    public void indexesShouldExist(DataTable table) throws SQLException {
        for (Map<String, String> row : table.asMaps()) {
            try (PreparedStatement ps = connection.prepareStatement(
                    "SELECT count(*) FROM pg_indexes " +
                    "WHERE schemaname='public' AND tablename=? AND indexname=?")) {
                ps.setString(1, row.get("table_name"));
                ps.setString(2, row.get("index_name"));
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    assertThat(rs.getInt(1)).as("索引 '%s' 應存在", row.get("index_name")).isEqualTo(1);
                }
            }
        }
    }

    @當("我統計各表的資料筆數")
    public void countTableRows() { }

    @那麼("各表資料筆數不低於:")
    public void rowCountsShouldMeetMinimum(DataTable table) throws SQLException {
        for (Map<String, String> row : table.asMaps()) {
            String t = sanitizeTableName(row.get("table_name"));
            int min = Integer.parseInt(row.get("min_count"));
            try (Statement st = connection.createStatement();
                 ResultSet rs = st.executeQuery("SELECT count(*) FROM " + t)) {
                rs.next();
                int actual = rs.getInt(1);
                assertThat(actual).as("表 '%s' 至少 %d 筆", t, min).isGreaterThanOrEqualTo(min);
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
                for (int i = 1; i <= cols; i++) {
                    r.put(md.getColumnLabel(i), rs.getString(i));
                }
                lastRows.add(r);
            }
        }
    }

    @那麼("查詢結果應為空集合")
    public void resultShouldBeEmpty() {
        assertThat(lastRows).as("應無孤立記錄").isEmpty();
    }

    @當("我查詢 owners 表中 first_name 為 {string} 的記錄")
    public void queryOwnerByFirstName(String firstName) throws SQLException {
        lastRows.clear();
        try (PreparedStatement ps = connection.prepareStatement(
                "SELECT * FROM owners WHERE first_name = ?")) {
            ps.setString(1, firstName);
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData md = rs.getMetaData();
                int cols = md.getColumnCount();
                while (rs.next()) {
                    Map<String, String> r = new LinkedHashMap<>();
                    for (int i = 1; i <= cols; i++) {
                        r.put(md.getColumnLabel(i), rs.getString(i));
                    }
                    lastRows.add(r);
                }
            }
        }
    }

    @那麼("應返回 {int} 筆記錄")
    public void shouldReturnNRecords(int expected) {
        assertThat(lastRows).as("回傳筆數").hasSize(expected);
    }

    @那麼("該記錄的欄位值為:")
    public void recordFieldsShouldMatch(DataTable table) {
        assertThat(lastRows).as("需要至少一筆記錄").isNotEmpty();
        Map<String, String> row = lastRows.get(0);
        for (Map<String, String> kv : table.asMaps()) {
            String field = kv.get("field");
            String want  = kv.get("value");
            assertThat(row).as("該記錄應包含欄位 '%s'", field).containsKey(field);
            assertThat(row.get(field)).as("欄位 '%s'", field).isEqualTo(want);
        }
    }

    @當("我對 owners 表插入一筆測試記錄:")
    public void insertTestOwner(DataTable table) throws SQLException {
        Map<String, String> d = table.asMaps().get(0);
        try (PreparedStatement ps = connection.prepareStatement(
                "INSERT INTO owners (first_name, last_name, address, telephone) " +
                "VALUES (?, ?, ?, ?) RETURNING id")) {
            ps.setString(1, d.get("first_name"));
            ps.setString(2, d.get("last_name"));
            ps.setString(3, d.get("address"));
            ps.setString(4, d.get("telephone"));
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                lastInsertedId = rs.getInt("id");
            }
        }
    }

    @那麼("插入應成功")
    public void insertShouldSucceed() {
        assertThat(lastInsertedId).isGreaterThan(0);
    }

    @那麼("返回的 id 應大於 {int}")
    public void idShouldBeGreaterThan(int v) {
        assertThat(lastInsertedId).isGreaterThan(v);
    }

    @當("我刪除該筆測試記錄")
    public void deleteTestRecord() throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(
                "DELETE FROM owners WHERE id = ?")) {
            ps.setInt(1, lastInsertedId);
            int n = ps.executeUpdate();
            assertThat(n).as("應刪除一筆").isEqualTo(1);
        }
    }

    @那麼("刪除應成功")
    public void deleteShouldSucceed() { /* assertion done above */ }

    private String sanitizeTableName(String name) {
        if (!name.matches("^[a-zA-Z_][a-zA-Z0-9_]*$"))
            throw new IllegalArgumentException("Invalid table name: " + name);
        return name;
    }
}
