package contracts.owners

import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "Update owner address — consumer api-gateway 預期回 204 No Content"
    request {
        method 'PUT'
        url '/owners/1'
        headers { contentType applicationJson() }
        body([
            id        : 1,
            firstName : "George",
            lastName  : "Franklin",
            address   : "Updated 999",
            city      : "Madison",
            telephone : "6085551023"
        ])
    }
    response {
        status 204
    }
}
