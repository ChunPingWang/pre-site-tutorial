package contracts.pets

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "List pet types — consumer api-gateway 預期 6 種寵物類型"
    request {
        method 'GET'
        url '/petTypes'
    }
    response {
        status 200
        headers { contentType applicationJson() }
        body('''[
          {"id":1,"name":"cat"},
          {"id":2,"name":"dog"},
          {"id":3,"name":"lizard"},
          {"id":4,"name":"snake"},
          {"id":5,"name":"bird"},
          {"id":6,"name":"hamster"}
        ]''')
        bodyMatchers {
            jsonPath('$', byType { minOccurrence(6) })
            jsonPath('$[0].name', byRegex('cat|dog|lizard|snake|bird|hamster'))
        }
    }
}
