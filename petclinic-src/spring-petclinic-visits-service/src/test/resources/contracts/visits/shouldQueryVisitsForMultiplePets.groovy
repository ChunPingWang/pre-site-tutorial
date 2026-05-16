package contracts.visits

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "Batch query visits for multiple pets (used by api-gateway when rendering owner detail with all pets)"
    request {
        method 'GET'
        url '/pets/visits?petId=7&petId=8'
    }
    response {
        status 200
        headers { contentType applicationJson() }
        body('''{"items":[
          {"id":1,"petId":7,"date":"2013-01-01","description":"rabies shot"},
          {"id":2,"petId":8,"date":"2013-01-02","description":"rabies shot"}
        ]}''')
        bodyMatchers {
            jsonPath('$.items',          byType { minOccurrence(0) })
            jsonPath('$.items[*].petId', byRegex('[0-9]+'))
        }
    }
}
