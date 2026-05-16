package contracts.owners

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "Return owner detail by ID — used by api-gateway when assembling owner page"
    request {
        method 'GET'
        url '/owners/1'
    }
    response {
        status 200
        headers { contentType applicationJson() }
        body([
            id        : 1,
            firstName : "George",
            lastName  : "Franklin",
            address   : "110 W. Liberty St.",
            city      : "Madison",
            telephone : "6085551023"
        ])
        bodyMatchers {
            jsonPath('$.id',        byRegex('[0-9]+'))
            jsonPath('$.firstName', byRegex('.+'))
            jsonPath('$.lastName',  byRegex('.+'))
        }
    }
}
