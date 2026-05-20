package com.presit.support;

import io.cucumber.java.Before;
import org.flywaydb.core.Flyway;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Starts a Testcontainers Postgres and runs Flyway migrations when
 * -Dcontract.test=true (activated by the phase-1-contract Maven profile).
 *
 * In K8s (contract.test=false), this hook is a no-op and DatabaseLayerSteps
 * continues to use DB_HOST / DB_PORT environment variables as before.
 */
public class ContractTestHooks {

    private static volatile PostgreSQLContainer<?> postgres;

    @Before(value = "@database", order = -1000)
    public void startPostgresIfContractMode() {
        if (!Boolean.getBoolean("contract.test")) return;
        if (isRunning()) {
            exportConnectionProps();
            return;
        }
        synchronized (ContractTestHooks.class) {
            if (!isRunning()) {
                // TC strategy detection is lazy (fires on container.start()).
                // Set docker.host before start() so EnvironmentAndSystemPropertyClientProviderStrategy
                // activates when DOCKER_HOST env var isn't inherited by the Surefire forked JVM.
                if (System.getenv("DOCKER_HOST") == null && System.getProperty("docker.host") == null) {
                    System.setProperty("docker.host", "unix:///var/run/docker.sock");
                }
                @SuppressWarnings("resource")
                PostgreSQLContainer<?> c = new PostgreSQLContainer<>("postgres:15-alpine")
                        .withDatabaseName("petclinic")
                        .withUsername("petclinic")
                        .withPassword("petclinic");
                c.start();

                for (String schema : new String[]{"customers_schema", "vets_schema", "visits_schema"}) {
                    Flyway.configure()
                            .dataSource(c.getJdbcUrl(), "petclinic", "petclinic")
                            .schemas(schema)
                            .locations("classpath:db/" + schema)
                            .load()
                            .migrate();
                }

                Runtime.getRuntime().addShutdownHook(new Thread(c::stop));
                postgres = c;
            }
        }
        exportConnectionProps();
    }

    private static boolean isRunning() {
        return postgres != null && postgres.isRunning();
    }

    private static void exportConnectionProps() {
        System.setProperty("db.host", postgres.getHost());
        System.setProperty("db.port", String.valueOf(postgres.getMappedPort(5432)));
        System.setProperty("db.name", "petclinic");
        System.setProperty("db.user", "petclinic");
        System.setProperty("db.password", "petclinic");
    }
}
