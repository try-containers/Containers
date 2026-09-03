//
//  PublishPortTests.swift
//  ContainerSystemTests
//
//  Clashes between the ports a container publishes.
//

import ContainerizationExtras
import Foundation
import Testing

@testable import ContainerSystem

@Suite("Published ports")
struct PublishPortTests {

    private func port(
        host: UInt16,
        container: UInt16 = 80,
        proto: PublishProtocol = .tcp,
        count: UInt16 = 1
    ) -> PublishPort {
        PublishPort(
            hostPort: host,
            containerPort: container,
            proto: proto,
            count: count
        )
    }

    @Test("Distinct host ports do not clash")
    func distinctPortsDoNotOverlap() {
        #expect(!([port(host: 8080), port(host: 8081)]).hasOverlaps())
    }

    @Test("The same host port twice clashes")
    func duplicatePortOverlaps() {
        // Different container ports still fight over the one host port.
        #expect(
            ([
                port(host: 8080, container: 80),
                port(host: 8080, container: 443),
            ])
            .hasOverlaps()
        )
    }

    @Test("A range clashes with a port that falls inside it")
    func rangeCoversPort() {
        #expect(([port(host: 8080, count: 5), port(host: 8082)]).hasOverlaps())
    }

    @Test("Ranges that only touch do not clash")
    func adjacentRangesDoNotOverlap() {
        // 8080-8082 then 8083-8084.
        #expect(
            !([port(host: 8080, count: 3), port(host: 8083, count: 2)])
                .hasOverlaps()
        )
    }

    @Test("Overlapping ranges clash")
    func overlappingRangesOverlap() {
        #expect(
            ([port(host: 8080, count: 4), port(host: 8082, count: 3)])
                .hasOverlaps()
        )
    }

    @Test("The same port on TCP and UDP does not clash")
    func protocolsAreSeparate() {
        #expect(
            !([port(host: 8080, proto: .tcp), port(host: 8080, proto: .udp)])
                .hasOverlaps()
        )
    }

    @Test("Nothing published cannot clash")
    func emptyDoesNotOverlap() {
        #expect(!([PublishPort]()).hasOverlaps())
    }

    @Test("A range running past the last port is counted without overflowing")
    func rangeOverflowingPortRange() {
        // A count that carries 65535 past the end of the range: tallied in
        // UInt16 that traps instead of reporting anything.
        #expect(!([port(host: 65535, count: 2)]).hasOverlaps())
        #expect(
            ([port(host: 65535, count: 2), port(host: 65535)]).hasOverlaps()
        )
    }

    @Test(
        "A protocol is read from its name, and anything else is TCP",
        arguments: [
            ("udp", PublishProtocol.udp), ("UDP", .udp),
            ("tcp", .tcp), ("sctp", .tcp), ("", .tcp),
        ]
    )

    func parsesProtocol(_ value: String, _ expected: PublishProtocol) {
        #expect(PublishProtocol(value) == expected)
    }
}
