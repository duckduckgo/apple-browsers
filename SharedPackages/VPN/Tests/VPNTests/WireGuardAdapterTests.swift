//
//  WireGuardAdapterTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import NetworkExtension
import Network
@testable import VPN

final class WireGuardAdapterTests: XCTestCase {

    private var adapter: WireGuardAdapter!
    private var tunnelConfiguration: TunnelConfiguration!
    private var peerEndpoint: Endpoint!
    private var packetTunnelProvider: MockPacketTunnelProvider!
    private var wireGuardInterface: MockWireGuardInterface!
    private var eventHandler: MockEventHandler!
    private var dnsResolver: MockDNSResolver!
    private var settingsGenerator: MockPacketTunnelSettingsGenerator!
    private var pathMonitor: MockPathMonitor!
    private var tunnelFileDescriptorProvider: MockTunnelFileDescriptorProvider!
    private var expectedNetworkSettings: NEPacketTunnelNetworkSettings!
    private var capturedResolvedEndpoints: [Endpoint?]?

    override func setUp() {
        super.setUp()

        packetTunnelProvider = MockPacketTunnelProvider()
        wireGuardInterface = MockWireGuardInterface()
        eventHandler = MockEventHandler()
        dnsResolver = MockDNSResolver(
            results: [.success(Endpoint(host: .ipv4(IPv4Address("203.0.113.1")!), port: 51820))]
        )
        settingsGenerator = MockPacketTunnelSettingsGenerator()
        expectedNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settingsGenerator.networkSettingsToReturn = expectedNetworkSettings
        settingsGenerator.uapiConfigurationReturnValue = ("mock-config", [nil])

        pathMonitor = MockPathMonitor()
        tunnelFileDescriptorProvider = MockTunnelFileDescriptorProvider(fileDescriptor: 42)

        peerEndpoint = Endpoint(host: NWEndpoint.Host("example.com"), port: 51820)
        var peer = PeerConfiguration(publicKey: Self.makePublicKey())
        peer.endpoint = peerEndpoint
        tunnelConfiguration = TunnelConfiguration.make(named: "Test", peers: [peer])

        adapter = WireGuardAdapter(
            with: packetTunnelProvider,
            wireGuardInterface: wireGuardInterface,
            eventHandler: eventHandler,
            logHandler: { _, _ in },
            pathMonitorProvider: { self.pathMonitor },
            packetTunnelSettingsGeneratorProvider: { _, resolvedEndpoints in
                self.capturedResolvedEndpoints = resolvedEndpoints
                return self.settingsGenerator
            },
            dnsResolver: dnsResolver,
            tunnelFileDescriptorProvider: tunnelFileDescriptorProvider
        )
    }

    override func tearDown() {
        adapter = nil
        tunnelConfiguration = nil
        peerEndpoint = nil
        packetTunnelProvider = nil
        wireGuardInterface = nil
        eventHandler = nil
        dnsResolver = nil
        settingsGenerator = nil
        pathMonitor = nil
        tunnelFileDescriptorProvider = nil
        expectedNetworkSettings = nil
        capturedResolvedEndpoints = nil
        super.tearDown()
    }

    func testStartHappyPathConfiguresNetworkAndBackend() {
        let startExpectation = expectation(description: "Start completes")

        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            XCTAssertNil(error)
            startExpectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(dnsResolver.receivedEndpoints?.count, 1)
        XCTAssertEqual(dnsResolver.receivedEndpoints?.first??.description, peerEndpoint.description)
        XCTAssertEqual(capturedResolvedEndpoints?.first??.description, "203.0.113.1:51820")

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1)
        XCTAssertTrue(packetTunnelProvider.lastNetworkSettings === expectedNetworkSettings)

        XCTAssertEqual(settingsGenerator.generateNetworkSettingsCallCount, 1)
        XCTAssertEqual(settingsGenerator.uapiConfigurationCallCount, 1)

        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 1)
        XCTAssertEqual(wireGuardInterface.lastTurnOnConfig, "mock-config")
        XCTAssertEqual(wireGuardInterface.lastTurnOnHandle, 42)

        XCTAssertEqual(pathMonitor.startCallCount, 1)
    }

    func testStartFailsWhenAlreadyRunning() {
        let firstStart = expectation(description: "Initial start succeeds")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            XCTAssertNil(error)
            firstStart.fulfill()
        }
        wait(for: [firstStart], timeout: 1.0)

        let secondStart = expectation(description: "Second start returns invalid state")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            guard case .invalidState(let reason) = error,
                  reason == .alreadyStarted else {
                XCTFail("Expected alreadyStarted error, got \(String(describing: error))")
                return
            }
            secondStart.fulfill()
        }
        wait(for: [secondStart], timeout: 1.0)

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1, "Should not reapply settings")
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 1, "Should not restart backend")
        XCTAssertEqual(pathMonitor.startCallCount, 1, "Should not start a second path monitor")
    }

    private static func makePublicKey() -> PublicKey {
        let hexKey = String(repeating: "ab", count: 32) // 32 bytes -> 64 hex characters
        return PublicKey(hexKey: hexKey)!
    }

}

// MARK: - Mocks

private final class MockPacketTunnelProvider: PacketTunnelProviding {
    var reasserting: Bool = false
    private(set) var setTunnelNetworkSettingsCallCount = 0
    private(set) var lastNetworkSettings: NETunnelNetworkSettings?
    var setTunnelNetworkSettingsError: Error?

    func setTunnelNetworkSettings(_ tunnelNetworkSettings: NETunnelNetworkSettings?, completionHandler: (@Sendable (Error?) -> Void)?) {
        setTunnelNetworkSettingsCallCount += 1
        lastNetworkSettings = tunnelNetworkSettings
        if let completionHandler {
            DispatchQueue.global().async {
                completionHandler(self.setTunnelNetworkSettingsError)
            }
        }
    }
}

private final class MockEventHandler: WireGuardAdapterEventHandling {
    private(set) var handledEvents: [WireGuardAdapterEvent] = []

    func handle(_ event: WireGuardAdapterEvent) {
        handledEvents.append(event)
    }
}

private final class MockPathMonitor: PathMonitoring {
    var pathUpdateHandler: ((Network.NWPath) -> Void)?
    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0

    func start(queue: DispatchQueue) {
        startCallCount += 1
    }

    func cancel() {
        cancelCallCount += 1
    }
}

private final class MockPacketTunnelSettingsGenerator: PacketTunnelSettingsGenerating {
    var networkSettingsToReturn = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    var uapiConfigurationReturnValue: (String, [EndpointResolutionResult?]) = ("", [])
    var endpointUapiConfigurationReturnValue: (String, [EndpointResolutionResult?]) = ("", [])

    private(set) var generateNetworkSettingsCallCount = 0
    private(set) var uapiConfigurationCallCount = 0

    func uapiConfiguration() -> (String, [EndpointResolutionResult?]) {
        uapiConfigurationCallCount += 1
        return uapiConfigurationReturnValue
    }

    func endpointUapiConfiguration() -> (String, [EndpointResolutionResult?]) {
        endpointUapiConfigurationReturnValue
    }

    func generateNetworkSettings() -> NEPacketTunnelNetworkSettings {
        generateNetworkSettingsCallCount += 1
        return networkSettingsToReturn
    }
}

private final class MockDNSResolver: DNSResolving {
    var receivedEndpoints: [Endpoint?]?
    var results: [Result<Endpoint, DNSResolutionError>?]

    init(results: [Result<Endpoint, DNSResolutionError>?]) {
        self.results = results
    }

    func resolveSync(endpoints: [Endpoint?]) -> [Result<Endpoint, DNSResolutionError>?] {
        receivedEndpoints = endpoints
        return results
    }
}

private final class MockTunnelFileDescriptorProvider: TunnelFileDescriptorProviding {
    let fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func currentFileDescriptor() -> Int32? {
        fileDescriptor
    }
}
