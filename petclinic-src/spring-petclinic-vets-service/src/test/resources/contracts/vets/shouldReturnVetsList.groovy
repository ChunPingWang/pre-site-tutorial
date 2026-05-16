package contracts.vets

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "List vets with specialties — consumer api-gateway 預期回獸醫含專長陣列"
    request {
        method 'GET'
        url '/vets'
    }
    response {
        status 200
        headers { contentType applicationJson() }
        body('''[
          {"id":2,"firstName":"Helen","lastName":"Leary","specialties":[{"id":1,"name":"radiology"}],"nrOfSpecialties":1}
        ]''')
        bodyMatchers {
            jsonPath('$',                       byType { minOccurrence(1) })
            jsonPath("\$[*].id",                byRegex('[0-9]+'))
            jsonPath("\$[*].firstName",         byRegex('.+'))
            jsonPath("\$[*].lastName",          byRegex('.+'))
            jsonPath("\$[*].specialties",       byType())
        }
    }
}
