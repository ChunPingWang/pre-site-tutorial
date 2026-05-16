package com.presit.runners;

import org.junit.platform.suite.api.*;

@Suite
@IncludeEngines("cucumber")
@SelectClasspathResource("features")
@ConfigurationParameter(key = "cucumber.glue",            value = "com.presit.steps")
@ConfigurationParameter(key = "cucumber.plugin",          value = "pretty,"
        + "html:reports/cucumber-report.html,"
        + "json:reports/cucumber-report.json,"
        + "junit:reports/cucumber-report.xml")
@ConfigurationParameter(key = "cucumber.execution.order", value = "lexical")
public class PreSitTestRunner {
}
