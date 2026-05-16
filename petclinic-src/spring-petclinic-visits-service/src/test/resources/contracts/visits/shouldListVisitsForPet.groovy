package contracts.visits

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "List visits for a pet — consumer api-gateway 預期回 visits 陣列"
    request {
        method 'GET'
        url '/owners/1/pets/7/visits'
    }
    response {
        status 200
        headers { contentType applicationJson() }
        body('''[
          {"id":1,"petId":7,"description":"rabies shot"}
        ]''')
        bodyMatchers {
            jsonPath('$',           byType { minOccurrence(0) })
            jsonPath('$[*].petId',  byRegex('[0-9]+'))
            jsonPath('$[*].id',     byRegex('[0-9]+'))
        }
    }
}
