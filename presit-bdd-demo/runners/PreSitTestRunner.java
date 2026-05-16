package com.presit.runners;

import org.junit.platform.suite.api.*;

/**
 * ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 * Pre-SIT 測試總控 Runner
 *
 * 對應架構圖中 Validation Layer 的 K8s Job 執行入口
 *
 * 執行策略：
 *   Phase 1 (@phase-1) → Phase 2 (@phase-2) →
 *   Phase 3 (@phase-3) → Phase 4 (@phase-4)
 *
 * 每個 Phase 均可獨立執行，也可依序串連
 * ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 */
@Suite
@IncludeEngines("cucumber")
@SelectDirectories("features")
@ConfigurationParameter(key = "cucumber.glue",               value = "com.presit.steps")
@ConfigurationParameter(key = "cucumber.plugin",             value = "pretty, "
        + "html:reports/cucumber-report.html, "
        + "json:reports/cucumber-report.json, "
        + "junit:reports/cucumber-report.xml, "
        + "me.jvt.cucumber.report.PrettyReports:reports/pretty")
@ConfigurationParameter(key = "cucumber.execution.order",    value = "lexical")
@ConfigurationParameter(key = "cucumber.snippet-type",       value = "camelcase")
public class PreSitTestRunner {
    // JUnit Platform 會自動掃描 features 目錄下的 .feature 檔
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 以下為各 Phase 獨立 Runner，方便單獨執行
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// --- Phase 1: 數據庫層 ---
// mvn test -Dcucumber.filter.tags="@phase-1"

// --- Phase 2: 應用層 ---
// mvn test -Dcucumber.filter.tags="@phase-2"

// --- Phase 3: 功能與集成 ---
// mvn test -Dcucumber.filter.tags="@phase-3"

// --- Phase 4: 端到端與決策 ---
// mvn test -Dcucumber.filter.tags="@phase-4"

// --- 只跑 Smoke Test ---
// mvn test -Dcucumber.filter.tags="@smoke"

// --- 只跑 Critical ---
// mvn test -Dcucumber.filter.tags="@critical"

// --- 完整流程（預設） ---
// mvn test -Dcucumber.filter.tags="@pre-sit"
