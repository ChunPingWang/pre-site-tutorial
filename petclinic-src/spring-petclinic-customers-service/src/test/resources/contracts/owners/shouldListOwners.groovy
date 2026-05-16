package contracts.owners

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "List all owners — consumer api-gateway 預期回 owner array"
    request {
        method 'GET'
        url '/owners'
    }
    response {
        status 200
        headers { contentType applicationJson() }
        body('''[{"id":1,"firstName":"George","lastName":"Franklin"}]''')
        bodyMatchers {
            jsonPath('$', byType { minOccurrence(1) })
            jsonPath('$[0].id',        byRegex('[0-9]+'))
            jsonPath('$[0].firstName', byRegex('.+'))
        }
    }
}
