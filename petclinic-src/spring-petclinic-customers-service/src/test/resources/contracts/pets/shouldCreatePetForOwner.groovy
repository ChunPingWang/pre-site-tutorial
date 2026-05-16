package contracts.pets

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "Create pet under an owner — consumer api-gateway 預期 201 + pet id"
    request {
        method 'POST'
        url '/owners/1/pets'
        headers { contentType applicationJson() }
        body([
            name      : "TestDog",
            birthDate : "2024-01-15",
            typeId    : 2
        ])
    }
    response {
        status 201
        headers { contentType applicationJson() }
        body([
            id        : 14,
            name      : "TestDog",
            birthDate : "2024-01-15",
            type      : [id: 2, name: "dog"]
        ])
        bodyMatchers {
            jsonPath('$.id',        byRegex('[0-9]+'))
            jsonPath('$.birthDate', byRegex('2024-01-15.*'))  // accept Date 序列化長/短格式
        }
    }
}
