package contracts.visits

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "Create visit for pet — consumer api-gateway 預期回 201 + visit id"
    request {
        method 'POST'
        url '/owners/1/pets/7/visits'
        headers { contentType applicationJson() }
        body([
            date        : "2026-05-16",
            description : "Annual checkup"
        ])
    }
    response {
        status 201
        headers { contentType applicationJson() }
        body([
            id          : 100,
            petId       : 7,
            date        : "2026-05-16",
            description : "Annual checkup"
        ])
        bodyMatchers {
            jsonPath('$.id', byRegex('[0-9]+'))
        }
    }
}
