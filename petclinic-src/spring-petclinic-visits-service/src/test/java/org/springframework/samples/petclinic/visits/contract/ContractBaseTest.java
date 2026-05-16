package org.springframework.samples.petclinic.visits.contract;

import io.restassured.module.mockmvc.RestAssuredMockMvc;
import org.junit.jupiter.api.BeforeEach;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.samples.petclinic.visits.model.*;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.context.WebApplicationContext;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;

/**
 * v2.2 Stage A.6 — visits-service contract provider base.
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
    @MockBean   private VisitRepository visitRepository;

    @BeforeEach
    void setup() {
        RestAssuredMockMvc.webAppContextSetup(context);
        seedVisits();
    }

    private void seedVisits() {
        Visit v1 = newVisit(1, 7, LocalDate.of(2013, 1, 1), "rabies shot");
        Visit v2 = newVisit(2, 8, LocalDate.of(2013, 1, 2), "rabies shot");

        // GET /owners/1/pets/7/visits → repo.findByPetId(7)
        Mockito.when(visitRepository.findByPetId(7)).thenReturn(List.of(v1));

        // GET /pets/visits?petId=7&petId=8 → repo.findByPetIdIn([7,8])
        Mockito.when(visitRepository.findByPetIdIn(List.of(7, 8))).thenReturn(List.of(v1, v2));

        // POST → save() returns visit with id=100
        Mockito.when(visitRepository.save(Mockito.any(Visit.class))).thenAnswer(inv -> {
            Visit v = inv.getArgument(0);
            if (v.getId() == null) setVisitId(v, 100);
            return v;
        });
    }

    private static Visit newVisit(int id, int petId, LocalDate date, String desc) {
        return Visit.visit()
                .id(id)
                .petId(petId)
                .date(Date.from(date.atStartOfDay(ZoneId.systemDefault()).toInstant()))
                .description(desc)
                .build();
    }

    private static void setVisitId(Visit v, int id) {
        try {
            java.lang.reflect.Field f = Visit.class.getDeclaredField("id");
            f.setAccessible(true);
            f.set(v, id);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
