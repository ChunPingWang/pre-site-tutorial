package org.springframework.samples.petclinic.customers.contract;

import io.restassured.module.mockmvc.RestAssuredMockMvc;
import org.junit.jupiter.api.BeforeEach;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.samples.petclinic.customers.model.*;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.context.WebApplicationContext;

import java.util.*;

/**
 * v2.2 Stage A.6 — Spring Cloud Contract provider-side test base.
 *
 * 此類別被 SCC plugin 自動產生的測試類別繼承（位置：
 * target/generated-test-sources/contracts/.../ContractVerifierTest.java）。
 * 我們在 @BeforeEach 中：
 *   1) 用 RestAssuredMockMvc 接 Spring MVC context
 *   2) Mock repository 回傳契約預期的資料
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.MOCK,
    properties = {
        // Contract test 用 @MockBean 取代 repository，不需要實際 DB
        "spring.autoconfigure.exclude=" +
            "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration," +
            "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration," +
            "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration"
    })
@ActiveProfiles("contract-test")
public abstract class ContractBaseTest {

    @Autowired private WebApplicationContext context;
    @MockBean   private OwnerRepository ownerRepository;
    @MockBean   private PetRepository   petRepository;

    @BeforeEach
    void setup() {
        RestAssuredMockMvc.webAppContextSetup(context);
        seedOwners();
        seedPetTypes();
        seedPets();
    }

    private void seedOwners() {
        Owner george = new Owner();
        george.setFirstName("George");
        george.setLastName("Franklin");
        george.setAddress("110 W. Liberty St.");
        george.setCity("Madison");
        george.setTelephone("6085551023");
        setOwnerId(george, 1);
        Mockito.when(ownerRepository.findById(1)).thenReturn(Optional.of(george));
        Mockito.when(ownerRepository.findAll()).thenReturn(List.of(george));

        // For POST /owners contract — return new id=11
        Mockito.when(ownerRepository.save(Mockito.any(Owner.class))).thenAnswer(inv -> {
            Owner o = inv.getArgument(0);
            if (o.getId() == null) setOwnerId(o, 11);
            return o;
        });
    }

    private void seedPetTypes() {
        List<PetType> types = new ArrayList<>();
        String[] names = {"cat","dog","lizard","snake","bird","hamster"};
        for (int i = 0; i < names.length; i++) {
            PetType t = new PetType();
            t.setId(i + 1);
            t.setName(names[i]);
            types.add(t);
        }
        Mockito.when(petRepository.findPetTypes()).thenReturn(types);
        Mockito.when(petRepository.findPetTypeById(2)).thenReturn(Optional.of(types.get(1)));
    }

    private void seedPets() {
        Mockito.when(petRepository.save(Mockito.any(Pet.class))).thenAnswer(inv -> {
            Pet p = inv.getArgument(0);
            if (p.getId() == null) setPetId(p, 14);
            return p;
        });
    }

    // id 在 Owner/Pet 本體（無 superclass），透過 reflection 設值
    private static void setOwnerId(Owner o, int id) { setIdField(o, Owner.class, id); }
    private static void setPetId(Pet p, int id)     { setIdField(p, Pet.class,   id); }

    private static void setIdField(Object obj, Class<?> cls, int id) {
        try {
            java.lang.reflect.Field f = cls.getDeclaredField("id");
            f.setAccessible(true);
            f.set(obj, id);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
