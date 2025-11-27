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
    private var eventHandler: MockWireGuardAdapterEventHandler!
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
        eventHandler = MockWireGuardAdapterEventHandler()
        dnsResolver = MockDNSResolver(results: [.success(Endpoint(host: .ipv4(IPv4Address("1.1.1.1")!), port: 12345))])
        settingsGenerator = MockPacketTunnelSettingsGenerator()
        expectedNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settingsGenerator.networkSettingsToReturn = expectedNetworkSettings
        settingsGenerator.uapiConfigurationReturnValue = ("mock-config", [nil])

        pathMonitor = MockPathMonitor()
        tunnelFileDescriptorProvider = MockTunnelFileDescriptorProvider(fileDescriptor: 42)

        peerEndpoint = Endpoint(host: NWEndpoint.Host("example.com"), port: 12345)
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

    func testAdapterStartConfiguresNetworkAndBackend() {
        let startExpectation = expectation(description: "Start completes")

        adapter.start(tunnelConfiguration: tunnelConfiguration) { error in
            XCTAssertNil(error)
            startExpectation.fulfill()
        }

        waitForExpectations(timeout: 10.0)

        XCTAssertEqual(dnsResolver.receivedEndpoints?.count, 1)
        XCTAssertEqual(dnsResolver.receivedEndpoints?.first??.description, peerEndpoint.description)
        XCTAssertEqual(capturedResolvedEndpoints?.first??.description, "1.1.1.1:12345")

        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 1)
        XCTAssertTrue(packetTunnelProvider.lastNetworkSettings === expectedNetworkSettings)

        XCTAssertEqual(settingsGenerator.generateNetworkSettingsCallCount, 1)
        XCTAssertEqual(settingsGenerator.uapiConfigurationCallCount, 1)

        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 1)
        XCTAssertEqual(wireGuardInterface.lastTurnOnConfig, "mock-config")
        XCTAssertEqual(wireGuardInterface.lastTurnOnHandle, 42)

        XCTAssertEqual(pathMonitor.startCallCount, 1)
    }

    func testAdapterStartFailsWhenAlreadyRunning() {
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

    func testAdapterStartFailsWhenDnsResolutionFails() {
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

    func testAdapterStartFailsWhenSettingNetworkSettingsFails() {
        packetTunnelProvider.setTunnelNetworkSettingsError = TestError.someError
        packetTunnelProvider.setTunnelNetworkSettingsDelay = .milliseconds(10)

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

    func testAdapterStartFailsWhenTunnelFileDescriptorMissing() {
        tunnelFileDescriptorProvider.fileDescriptor = nil

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

    func testAdapterStartFailsWhenTurnOnReturnsError() {
        wireGuardInterface.turnOnReturnHandle = -5

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

    func testAdapterStopTransitionsToStoppedAndSecondCallErrors() {
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

    func testUpdateWithReassertFalseDoesNotToggleReasserting() {
        startAdapterSuccessfully()

        let expectation = expectation(description: "Update succeeds without reassert")
        adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: false) { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertFalse(packetTunnelProvider.reasserting, "Reasserting should remain false when reassert is disabled")
        XCTAssertEqual(wireGuardInterface.setConfigCallCount, 1)
    }

    func testUpdateFailsWhenSettingsGeneratorCannotBeCreated() {
        startAdapterSuccessfully()
        dnsResolver.results = [.failure(DNSResolutionError(errorCode: 2, address: "example.com"))]

        let expectation = expectation(description: "Update fails with DNS error")
        adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: true) { error in
            guard case .dnsResolution = error else {
                XCTFail("Expected dnsResolution error, got \(String(describing: error))")
                return
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)
    }

    #if os(iOS)
    func testPathStatusTransitionsThroughTemporaryShutdownAndRestart() {
        startAdapterSuccessfully()

        pathMonitor.emitStatus(.satisfied)
        XCTAssertEqual(settingsGenerator.endpointUapiConfigurationCallCount, 1)
        XCTAssertEqual(wireGuardInterface.setConfigCallCount, 1)
        XCTAssertEqual(wireGuardInterface.disableRoamingCallCount, 2)
        XCTAssertEqual(wireGuardInterface.bumpSocketsCallCount, 1)

        pathMonitor.emitStatus(.unsatisfied)
        XCTAssertEqual(wireGuardInterface.turnOffCallCount, 1)

        pathMonitor.emitStatus(.satisfied)
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 2)
        XCTAssertEqual(packetTunnelProvider.setTunnelNetworkSettingsCallCount, 2)
        XCTAssertTrue(eventHandler.handledEvents.isEmpty)
    }

    func testTemporaryShutdownRecoveryEvents() {
        startAdapterSuccessfully()
        pathMonitor.emitStatus(.unsatisfied)

        packetTunnelProvider.setTunnelNetworkSettingsError = TestError.someError
        pathMonitor.emitStatus(.satisfied)
        XCTAssertEqual(eventHandler.handledEvents.count, 1)
        if case .endTemporaryShutdownStateAttemptFailure(let error) = eventHandler.handledEvents[0] {
            guard let adapterError = error as? WireGuardAdapterError,
                  case .setNetworkSettings(let underlyingError) = adapterError else {
                XCTFail("Expected WireGuardAdapterError.setNetworkSettings, got \(error)")
                return
            }
            XCTAssertEqual(underlyingError as? TestError, .someError)
        } else {
            XCTFail("Expected attempt failure event")
        }

        pathMonitor.emitStatus(.satisfied)
        XCTAssertEqual(eventHandler.handledEvents.count, 2)
        if case .endTemporaryShutdownStateRecoveryFailure(let error) = eventHandler.handledEvents[1] {
            guard let adapterError = error as? WireGuardAdapterError,
                  case .setNetworkSettings(let underlyingError) = adapterError else {
                XCTFail("Expected WireGuardAdapterError.setNetworkSettings, got \(error)")
                return
            }
            XCTAssertEqual(underlyingError as? TestError, .someError)
        } else {
            XCTFail("Expected recovery failure event")
        }

        packetTunnelProvider.setTunnelNetworkSettingsError = nil
        pathMonitor.emitStatus(.satisfied)
        XCTAssertEqual(eventHandler.handledEvents.count, 3)
        if case .endTemporaryShutdownStateRecoverySuccess = eventHandler.handledEvents[2] {
            // success
        } else {
            XCTFail("Expected recovery success event")
        }

        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 2)
    }

    func testUpdateWhileTemporaryShutdownDoesNotRestartBackend() {
        startAdapterSuccessfully()
        pathMonitor.emitStatus(.unsatisfied)

        let expectation = expectation(description: "Update completes while temporary shutdown")
        adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: true) { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(wireGuardInterface.setConfigCallCount, 0, "Backend should not receive config while offline")
        XCTAssertEqual(wireGuardInterface.turnOnCallCount, 1, "Backend should not restart during update")
    }
    #elseif os(macOS)
    func testMacPathUpdateBumpsSockets() {
        startAdapterSuccessfully()
        pathMonitor.emitStatus(.satisfied)
        XCTAssertEqual(wireGuardInterface.bumpSocketsCallCount, 1)
    }
    #endif

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
