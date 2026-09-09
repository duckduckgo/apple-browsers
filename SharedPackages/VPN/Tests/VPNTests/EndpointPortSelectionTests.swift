//
//  EndpointPortSelectionTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
import Network
@testable import VPN

final class EndpointPortSelectionTests: XCTestCase {

    func testFirstRespondingCandidateWins_WhenItIsNotTheDefault() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820, 8080],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: [51820]
        )

        XCTAssertEqual(decision.port, 51820)
        XCTAssertEqual(decision.automaticPort, 51820)
        XCTAssertEqual(decision.rememberedPort, 51820)
    }

    func testServerDefaultWins_WhenItRespondsFirst() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 51820,
            serverDefaultPort: 443,
            responding: [443, 51820]
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertEqual(decision.rememberedPort, 443)
    }

    func testNothingResponds_CurrentPortAdvertisedAndNotTheDefault_KeepsCurrentPortAsAutomaticPort() {
        // Nothing answered, but currentPort (51820) still advertised by the server, so the next
        // regeneration must keep using it rather than falling back to the server default.
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 51820,
            serverDefaultPort: 443,
            responding: []
        )

        XCTAssertEqual(decision.port, 51820)
        XCTAssertEqual(decision.automaticPort, 51820)
        XCTAssertNil(decision.rememberedPort)
    }

    func testNothingResponds_CurrentPortIsTheDefault_AutomaticPortStaysNil() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: []
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertNil(decision.rememberedPort)
    }

    func testNothingResponds_CurrentPortNotAdvertised_FallsBackToServerDefault() {
        // currentPort (12345) is stale, carried over from a different server; it must not be forced
        // on a server that never advertised it.
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 12345,
            serverDefaultPort: 443,
            responding: []
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertNil(decision.rememberedPort)
    }

    func testRememberedPortFirstInCandidates_WinsOverDefault() {
        // The remembered port (51820) is ordered first by endpointPortCandidates(preferring:), so it wins
        // even though the server default (443) also answered.
        let decision = EndpointPortSelection.decide(
            candidates: [51820, 443],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: [443, 51820]
        )

        XCTAssertEqual(decision.port, 51820)
        XCTAssertEqual(decision.automaticPort, 51820)
        XCTAssertEqual(decision.rememberedPort, 51820)
    }

    func testRespondingPortsOutsideCandidates_AreIgnored() {
        let decision = EndpointPortSelection.decide(
            candidates: [443, 51820],
            currentPort: 443,
            serverDefaultPort: 443,
            responding: [9999]
        )

        XCTAssertEqual(decision.port, 443)
        XCTAssertNil(decision.automaticPort)
        XCTAssertNil(decision.rememberedPort)
    }

    func testSelect_ProbesAdvertisedPortsAndRewritesOnlyTheEndpointPort() async throws {
        let selector = EndpointPortSelection(prober: StubProber { host, ports in
            XCTAssertEqual(host, .ipv4(IPv4Address("192.0.2.1")!))
            XCTAssertEqual(ports, [443, 51820])
            return [51820]
        })
        let configuration = makeConfiguration(port: 443)

        let result = try await selector.select(for: makeServer(ports: [443, 51820]), in: configuration, preferring: nil)
        let selection = try XCTUnwrap(result)

        XCTAssertEqual(selection.configuration.peers.first?.endpoint?.port.rawValue, 51820)
        XCTAssertEqual(selection.configuration.peers.first?.endpoint?.host, configuration.peers.first?.endpoint?.host)
        XCTAssertEqual(selection.configuration.interface, configuration.interface)
        XCTAssertEqual(selection.decision.automaticPort, 51820)
        XCTAssertEqual(selection.decision.rememberedPort, 51820)
    }

    func testSelect_RememberedAdvertisedPortWinsWhenBothAnswer() async throws {
        let selector = EndpointPortSelection(prober: StubProber { _, ports in
            XCTAssertEqual(ports, [51820, 443])
            return [443, 51820]
        })

        let result = try await selector.select(for: makeServer(ports: [443, 51820]),
                                               in: makeConfiguration(port: 443),
                                               preferring: 51820)

        XCTAssertEqual(result?.configuration.peers.first?.endpoint?.port.rawValue, 51820)
    }

    func testSelect_NoResponsePreservesAnAdvertisedCurrentPortWithoutRememberingIt() async throws {
        let selector = EndpointPortSelection(prober: StubProber { _, _ in [] })

        let result = try await selector.select(for: makeServer(ports: [443, 51820]),
                                               in: makeConfiguration(port: 51820),
                                               preferring: nil)

        XCTAssertEqual(result?.configuration.peers.first?.endpoint?.port.rawValue, 51820)
        XCTAssertEqual(result?.decision.automaticPort, 51820)
        XCTAssertNil(result?.decision.rememberedPort)
    }

    func testSelect_SingleAdvertisedPortSkipsProbingAndDropsAnUnadvertisedCurrentPort() async throws {
        let selector = EndpointPortSelection(prober: StubProber { _, _ in
            XCTFail("A single advertised port must not be probed")
            return []
        })

        let result = try await selector.select(for: makeServer(ports: nil),
                                               in: makeConfiguration(port: 51820),
                                               preferring: 51820)

        XCTAssertEqual(result?.configuration.peers.first?.endpoint?.port.rawValue, 443)
        XCTAssertNil(result?.decision.automaticPort)
        XCTAssertNil(result?.decision.rememberedPort)
    }

    func testSelect_MissingPeerEndpointSkipsProbingAndReturnsNoSelection() async throws {
        let selector = EndpointPortSelection(prober: StubProber { _, _ in
            XCTFail("A configuration without an endpoint must not be probed")
            return []
        })

        let result = try await selector.select(for: makeServer(ports: [443, 51820]),
                                               in: .make(peers: []),
                                               preferring: nil)

        XCTAssertNil(result)
    }

    func testSelect_CancelledProbeCannotReturnASelectionEvenIfTheProberReturnsPorts() async {
        let task = Task {
            let selector = EndpointPortSelection(prober: StubProber { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return [51820]
            })
            return try await selector.select(for: makeServer(ports: [443, 51820]),
                                             in: makeConfiguration(port: 443),
                                             preferring: nil)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeServer(ports: [UInt16]?) -> NetworkProtectionServerInfo {
        NetworkProtectionServerInfo(name: "server", publicKey: "", hostNames: [],
                                    ips: [AnyIPAddress("192.0.2.1")!],
                                    internalIP: AnyIPAddress("10.0.0.1")!, port: 443, ports: ports,
                                    attributes: .init(city: "City", country: "Country", state: "State"))
    }

    private func makeConfiguration(port: UInt16) -> TunnelConfiguration {
        var peer = PeerConfiguration.make(publicKey: PrivateKey().publicKey)
        peer.endpoint = Endpoint(host: .ipv4(IPv4Address("192.0.2.1")!), port: NWEndpoint.Port(rawValue: port)!)
        return .make(peers: [peer])
    }

    private struct StubProber: EndpointPortProbing {
        let respond: (NWEndpoint.Host, [UInt16]) async throws -> Set<UInt16>

        func respondingPorts(host: NWEndpoint.Host, ports: [UInt16]) async throws -> Set<UInt16> {
            try await respond(host, ports)
        }
    }

}
