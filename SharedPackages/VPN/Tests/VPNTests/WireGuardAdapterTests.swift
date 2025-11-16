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
    private var settingsGeneratorProvider: WireGuardAdapter.PacketTunnelSettingsGeneratorProvider!

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

        settingsGeneratorProvider = { [weak self] _, resolvedEndpoints in
            guard let self else {
                return MockPacketTunnelSettingsGenerator()
            }
            self.capturedResolvedEndpoints = resolvedEndpoints
            return self.settingsGenerator
        }

        rebuildAdapter()
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
        settingsGeneratorProvider = nil
        super.tearDown()
    }

    private func rebuildAdapter() {
        capturedResolvedEndpoints = nil
        adapter = WireGuardAdapter(
            with: packetTunnelProvider,
            wireGuardInterface: wireGuardInterface,
            eventHandler: eventHandler,
            logHandler: { _, _ in },
            pathMonitorProvider: { self.pathMonitor },
            packetTunnelSettingsGeneratorProvider: settingsGeneratorProvider,
            dnsResolver: dnsResolver,
            tunnelFileDescriptorProvider: tunnelFileDescriptorProvider
        )
    }

    func testStartHappyPathConfiguresNetworkAndBackend() {
        let startExpectation = expectation(description: "Start completes")

        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            XCTAssertNil(error)
            startExpectation.fulfill()
        }

        waitForExpectations(timeout: 10.0)

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
        wait(for: [firstStart], timeout: 10.0)

        let secondStart = expectation(description: "Second start returns invalid state")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            guard case .invalidState(let reason) = error,
                  reason == .alreadyStarted else {
                XCTFail("Expected alreadyStarted error, got \(String(describing: error))")
                return
            }
            secondStart.fulfill()
        }
        wait(for: [secondStart], timeout: 10.0)

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1, "Should not reapply settings")
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 1, "Should not restart backend")
        XCTAssertEqual(pathMonitor.startCallCount, 1, "Should not start a second path monitor")
    }

    func testStartFailsWhenDnsResolutionFails() {
        dnsResolver.results = [.failure(DNSResolutionError(errorCode: 1, address: "example.com"))]

        let expectation = expectation(description: "Start fails with DNS error")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            guard case .dnsResolution = error else {
                XCTFail("Expected dnsResolution error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 0, "Should not set network settings")
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 0, "Should not start backend")
        XCTAssertEqual(pathMonitor.startCallCount, 1, "Path monitor starts before resolution attempt")
        XCTAssertEqual(pathMonitor.cancelCallCount, 1, "Path monitor should be cancelled on error")
    }

    func testStartFailsWhenSettingNetworkSettingsFails() {
        packetTunnelProvider.setTunnelNetworkSettingsError = TestError.someError

        let expectation = expectation(description: "Start fails with network settings error")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            guard case .setNetworkSettings(let underlyingError) = error,
                  (underlyingError as? TestError) == .someError else {
                XCTFail("Expected setNetworkSettings error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1)
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 0, "Backend should not start on failure")
        XCTAssertEqual(pathMonitor.startCallCount, 1, "Path monitor starts before applying settings")
        XCTAssertEqual(pathMonitor.cancelCallCount, 1, "Path monitor should be cancelled on failure")
    }

    func testStartFailsWhenTunnelFileDescriptorMissing() {
        tunnelFileDescriptorProvider = MockTunnelFileDescriptorProvider(fileDescriptor: nil)
        rebuildAdapter()

        let expectation = expectation(description: "Start fails with missing tunnel fd")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            guard case .cannotLocateTunnelFileDescriptor = error else {
                XCTFail("Expected cannotLocateTunnelFileDescriptor error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1)
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 0)
        XCTAssertEqual(pathMonitor.startCallCount, 1)
        XCTAssertEqual(pathMonitor.cancelCallCount, 1)
    }

    func testStartFailsWhenTurnOnReturnsError() {
        wireGuardInterface.turnOnReturnHandle = -5
        rebuildAdapter()

        let expectation = expectation(description: "Start fails when backend cannot start")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            guard case .startWireGuardBackend = error else {
                XCTFail("Expected startWireGuardBackend error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1)
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 1)
        XCTAssertEqual(pathMonitor.startCallCount, 1)
        XCTAssertEqual(pathMonitor.cancelCallCount, 1)
    }

    func testStopTransitionsToStoppedAndSecondCallErrors() {
        startAdapterSuccessfully()

        let stopExpectation = expectation(description: "Stop succeeds")
        adapter.stop { error in
            XCTAssertNil(error)
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 10.0)

        XCTAssertEqual(wireGuardInterface.turnOffCallCount, 1)
        XCTAssertEqual(pathMonitor.cancelCallCount, 1)

        let secondStop = expectation(description: "Second stop returns invalid state")
        adapter.stop { error in
            guard case .invalidState(let reason) = error,
                  reason == .alreadyStopped else {
                XCTFail("Expected alreadyStopped error, got \(String(describing: error))")
                return
            }
            secondStop.fulfill()
        }
        wait(for: [secondStop], timeout: 10.0)

        XCTAssertEqual(wireGuardInterface.turnOffCallCount, 1)
    }

    func testSnoozeTransitionsAndSecondCallNoops() {
        startAdapterSuccessfully()

        let snoozeExpectation = expectation(description: "Snooze succeeds")
        adapter.snooze { error in
            XCTAssertNil(error)
            snoozeExpectation.fulfill()
        }
        wait(for: [snoozeExpectation], timeout: 10.0)

        XCTAssertEqual(wireGuardInterface.turnOffCallCount, 1)
        XCTAssertEqual(pathMonitor.cancelCallCount, 1)
        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 2, "Should clear network settings")
        XCTAssertNil(packetTunnelProvider.lastNetworkSettings)

        let secondSnooze = expectation(description: "Second snooze succeeds but is a no-op")
        adapter.snooze { error in
            XCTAssertNil(error)
            secondSnooze.fulfill()
        }
        wait(for: [secondSnooze], timeout: 10.0)

        XCTAssertEqual(wireGuardInterface.turnOffCallCount, 1, "No additional turnOff expected")
        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 3, "Snoozing again still reapplies nil settings")
        XCTAssertEqual(pathMonitor.cancelCallCount, 1)
    }

    func testUpdateFailsWhenAdapterStopped() {
        let expectation = expectation(description: "Update when stopped returns invalid state")
        adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: true) { error in
            guard case .invalidState(let reason) = error,
                  reason == .updatedTunnelWhileStopped else {
                XCTFail("Expected invalidState(updatedTunnelWhileStopped), got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)
    }

    func testUpdateFromStartedReassertsAndConfiguresBackend() {
        startAdapterSuccessfully()
        wireGuardInterface.setConfigResult = 0

        let updateExpectation = expectation(description: "Update succeeds")
        adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: true) { error in
            XCTAssertNil(error)
            updateExpectation.fulfill()
        }
        wait(for: [updateExpectation], timeout: 10.0)

        XCTAssertFalse(packetTunnelProvider.reasserting, "Reasserting should be reset to false after update")
        XCTAssertEqual(settingsGenerator.generateNetworkSettingsCallCount, 2, "Second call during update")
        XCTAssertEqual(wireGuardInterface.setConfigCallCount, 1)
        XCTAssertEqual(wireGuardInterface.lastSetConfigHandle, wireGuardInterface.lastTurnOnResult)
        XCTAssertEqual(wireGuardInterface.lastSetConfig, "mock-config", "Reuses uapiConfiguration result")
    }

    func testUpdateFailsWhenSetConfigReturnsError() {
        startAdapterSuccessfully()
        wireGuardInterface.setConfigResult = -42

        let expectation = expectation(description: "Update propagates setConfig failure")
        adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: true) { error in
            guard case .setWireguardConfig = error else {
                XCTFail("Expected setWireguardConfig error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(wireGuardInterface.setConfigCallCount, 1)
        XCTAssertFalse(packetTunnelProvider.reasserting)
    }

    private static func makePublicKey() -> PublicKey {
        let hexKey = String(repeating: "ab", count: 32) // 32 bytes -> 64 hex characters
        return PublicKey(hexKey: hexKey)!
    }

    @discardableResult
    private func startAdapterSuccessfully(file: StaticString = #file, line: UInt = #line) -> XCTestExpectation {
        let startExpectation = expectation(description: "Adapter starts")
        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            XCTAssertNil(error, file: file, line: line)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 10.0)
        return startExpectation
    }

}

private enum TestError: Error, Equatable {
    case someError
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

private final class MockWireGuardInterface: WireGuardGoInterface {
    var turnOnCallCount = 0
    var lastTurnOnConfig: String?
    var lastTurnOnHandle: Int32?
    var lastTurnOnResult: Int32?
    var turnOnReturnHandle: Int32 = 7

    var turnOffCallCount = 0
    var lastTurnOffHandle: Int32?

    var setConfigCallCount = 0
    var lastSetConfigHandle: Int32?
    var lastSetConfig: String?
    var setConfigResult: Int64 = 0

    var bumpSocketsCallCount = 0
    var disableRoamingCallCount = 0

    var getConfigReturnValue: UnsafeMutablePointer<CChar>?

    var loggerContext: UnsafeMutableRawPointer?
    var loggerFunction: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void)?

    func turnOn(settings: UnsafePointer<CChar>, handle: Int32) -> Int32 {
        turnOnCallCount += 1
        lastTurnOnConfig = String(cString: settings)
        lastTurnOnHandle = handle
        let result = turnOnReturnHandle
        lastTurnOnResult = result
        return result
    }

    func turnOff(handle: Int32) {
        turnOffCallCount += 1
        lastTurnOffHandle = handle
    }

    func getConfig(handle: Int32) -> UnsafeMutablePointer<CChar>? {
        getConfigReturnValue
    }

    func setConfig(handle: Int32, config: String) -> Int64 {
        setConfigCallCount += 1
        lastSetConfigHandle = handle
        lastSetConfig = config
        return setConfigResult
    }

    func bumpSockets(handle: Int32) {
        bumpSocketsCallCount += 1
    }

    func disableSomeRoamingForBrokenMobileSemantics(handle: Int32) {
        disableRoamingCallCount += 1
    }

    func setLogger(context: UnsafeMutableRawPointer?, logFunction: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void)?) {
        loggerContext = context
        loggerFunction = logFunction
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
    var fileDescriptor: Int32?

    init(fileDescriptor: Int32?) {
        self.fileDescriptor = fileDescriptor
    }

    func currentFileDescriptor() -> Int32? {
        fileDescriptor
    }
}
