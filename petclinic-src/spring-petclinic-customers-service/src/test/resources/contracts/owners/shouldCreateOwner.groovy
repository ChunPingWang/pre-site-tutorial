package contracts.owners

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "Create owner — consumer api-gateway 預期回 201 + 新增 id"
    request {
        method 'POST'
        url '/owners'
        headers { contentType applicationJson() }
        body([
            firstName : "Jane",
            lastName  : "Doe",
            address   : "1 Test St.",
            city      : "Taipei",
            telephone : "0912345678"
        ])
    }
    response {
        status 201
        headers { contentType applicationJson() }
        body([
            id        : 11,
            firstName : "Jane",
            lastName  : "Doe",
            address   : "1 Test St.",
            city      : "Taipei",
            telephone : "0912345678"
        ])
        bodyMatchers {
            jsonPath('$.id', byRegex('[0-9]+'))
        }
    }
}
