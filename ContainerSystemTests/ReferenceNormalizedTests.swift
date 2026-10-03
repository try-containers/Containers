//
//  ReferenceNormalizedTests.swift
//  ContainerSystemTests
//
//  What a short image name is filled in to.
//

import ContainerizationOCI
import Testing

@testable import ContainerSystem

@Suite("Normalized references")
struct ReferenceNormalizedTests {

    @Test(
        "Short names are filled in as Docker Hub fills them in",
        arguments: [
            ("nginx", "docker.io/library/nginx:latest"),
            ("nginx:1.27", "docker.io/library/nginx:1.27"),
            ("bitnami/redis", "docker.io/bitnami/redis:latest"),
            ("docker.io/nginx", "docker.io/library/nginx:latest"),
            ("  alpine  ", "docker.io/library/alpine:latest"),
        ]
    )
    func dockerHub(reference: String, expected: String) throws {
        #expect(try Reference.normalized(reference).description == expected)
    }

    @Test(
        "A name with its own registry keeps it",
        arguments: [
            ("ghcr.io/apple/containerization/vminit:0.1", "ghcr.io/apple/containerization/vminit:0.1"),
            ("localhost:5000/app", "localhost:5000/app:latest"),
            ("registry.example.com/team/app", "registry.example.com/team/app:latest"),
        ]
    )
    func explicitRegistry(reference: String, expected: String) throws {
        #expect(try Reference.normalized(reference).description == expected)
    }

    @Test("A name that isn't a reference throws")
    func invalid() {
        #expect(throws: (any Error).self) {
            try Reference.normalized("Not A Reference!")
        }
    }
}
