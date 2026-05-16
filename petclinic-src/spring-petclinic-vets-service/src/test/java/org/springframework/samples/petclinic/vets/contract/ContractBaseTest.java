package org.springframework.samples.petclinic.vets.contract;

import io.restassured.module.mockmvc.RestAssuredMockMvc;
import org.junit.jupiter.api.BeforeEach;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.samples.petclinic.vets.model.*;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.context.WebApplicationContext;

import java.util.*;

/**
 * v2.2 Stage A.6 — vets-service contract provider base.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.MOCK,
    properties = {
        "spring.autoconfigure.exclude=" +
            "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration," +
            "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration," +
            "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration"
    })
@ActiveProfiles("contract-test")
public abstract class ContractBaseTest {

    @Autowired private WebApplicationContext context;
    @MockBean   private VetRepository vetRepository;

    @BeforeEach
    void setup() {
        RestAssuredMockMvc.webAppContextSetup(context);
        seedVets();
    }

    private void seedVets() {
        Vet james = newVet(1, "James", "Carter");
        Specialty radiology = newSpecialty(1, "radiology");
        Vet helen = newVet(2, "Helen", "Leary");
        helen.addSpecialty(radiology);
        Mockito.when(vetRepository.findAll()).thenReturn(List.of(james, helen));
    }

    private static Vet newVet(int id, String fn, String ln) {
        Vet v = new Vet();
        setId(v, Vet.class, id);
        v.setFirstName(fn);
        v.setLastName(ln);
        return v;
    }

    private static Specialty newSpecialty(int id, String name) {
        Specialty s = new Specialty();
        setId(s, Specialty.class, id);
        s.setName(name);
        return s;
    }

    private static void setId(Object obj, Class<?> cls, int id) {
        try {
            java.lang.reflect.Field f = cls.getDeclaredField("id");
            f.setAccessible(true);
            f.set(obj, id);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
