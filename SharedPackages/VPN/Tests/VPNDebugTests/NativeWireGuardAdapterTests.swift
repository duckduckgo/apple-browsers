//
//  NativeWireGuardAdapterTests.swift
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

#if DEBUG && (os(macOS) || os(iOS))
import Foundation
import Network
import NetworkExtension
import VPN
import XCTest
@testable import DuckWireGuard
@testable import VPNDebug

final class NativeWireGuardAdapterTests: XCTestCase {
    func testStartPreservesNetworkSettingsAndAutomaticMTU() throws {
        let harness = try Harness()
        harness.start(self)
        let settings = try XCTUnwrap(harness.packetIO.settings.first ?? nil)
#if os(iOS)
        XCTAssertEqual(settings.mtu, 1280)
        XCTAssertNil(settings.tunnelOverheadBytes)
#else
        XCTAssertNil(settings.mtu)
        XCTAssertEqual(settings.tunnelOverheadBytes, 80)
#endif
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["10.0.0.1"])
        XCTAssertEqual(settings.ipv4Settings?.includedRoutes?.first?.destinationAddress, "0.0.0.0")
        XCTAssertEqual(settings.dnsSettings?.servers, ["10.11.12.1"])
        XCTAssertEqual(harness.transports.transports.count, 1)
        XCTAssertEqual(harness.packetIO.readCount, 1)
    }

    func testExplicitMTUAndZeroAutomaticMTUPreserveProductionSettings() throws {
        for mtu in [UInt16(0), 1281, 1420, 9000] {
            let configuration = try Harness.configuration()
            configuration.interface.mtu = mtu
            let harness = try Harness(configuration: configuration)
            harness.start(self)
            let settings = try XCTUnwrap(harness.packetIO.settings.first ?? nil)
            if mtu == 0 {
#if os(iOS)
                XCTAssertEqual(settings.mtu, 1280)
                XCTAssertNil(settings.tunnelOverheadBytes)
#else
                XCTAssertNil(settings.mtu)
                XCTAssertEqual(settings.tunnelOverheadBytes, 80)
#endif
            } else {
                XCTAssertEqual(settings.mtu?.intValue, Int(mtu))
                XCTAssertNil(settings.tunnelOverheadBytes)
            }
            harness.stop(self)
        }
    }

    func testAutomaticMTUAllowsOutboundPacketsLargerThan1280() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let packet = Harness.packetWithLength(1401)
        harness.packetIO.deliver([packet])
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [packet])
        XCTAssertEqual(harness.droppedPacketCount, 0)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testAutomaticMTUPaddingUsesTheCachedTunnelMTUForIPv6OuterOverhead() throws {
        let harness = try Harness()
        harness.packetIO.interfaceMTU = 1420 // A 1500-byte path minus the IPv6/WireGuard overhead.
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 1)
        let packet = Harness.packetWithLength(1420)
        harness.packetIO.deliver([packet, packet])
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [packet, packet])
        XCTAssertEqual(transport.dataPackets.map { $0.count + 48 }, [1500, 1500], "IPv6 plus UDP must fit without padding over the effective tunnel MTU")
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), [1, 2])
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 1, "Packet encryption must not query the interface")
    }

    func testPathChangeInvalidatesAutomaticPaddingBeforeCoalescedRecovery() throws {
        let harness = try Harness()
        harness.packetIO.interfaceMTU = 1420
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        var recoveries: [() -> Void] = [] // Owner-queue-only deterministic path callbacks.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
        }
        harness.packetIO.interfaceMTU = 1300
        harness.adapter.queue.sync { harness.adapter.handleNetworkPathUpdate(status: .satisfied) }
        let boundary = Harness.packetWithLength(1300)
        harness.packetIO.deliver([boundary])
        harness.drain()
        XCTAssertEqual(old.dataPackets.map(\.count), [1332], "The old 1420-byte cache cannot add padding during recovery")
        XCTAssertEqual(try old.dataPackets.map(Harness.decrypt), [boundary])
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 1)
        harness.adapter.queue.sync { recoveries.removeFirst()() }
        harness.drain()
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertFalse(current === old)
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 2)
        let nearBoundary = Harness.packetWithLength(1297)
        harness.packetIO.deliver([nearBoundary])
        harness.drain()
        XCTAssertEqual(current.dataPackets.map(\.count), [1332], "Readiness refreshes the new 1300-byte padding cap")
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), [nearBoundary])
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testUnknownAutomaticMTUAddsNoPaddingAndKeepsTheIPPayload() throws {
        let unknownMTUs: [Int?] = [nil, 0, 65_536]
        for mtu in unknownMTUs {
            let harness = try Harness()
            harness.packetIO.interfaceMTU = mtu
            harness.start(self)
            let transport = try XCTUnwrap(harness.transports.transports.first)
            transport.deliver(Harness.response)
            harness.drain()
            let packet = Harness.packetWithLength(1401)
            harness.packetIO.deliver([packet, packet])
            harness.drain()
            XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [packet, packet])
            XCTAssertEqual(transport.dataPackets.map(\.count), [1401 + 32, 1401 + 32])
            XCTAssertEqual(transport.dataPackets.map(Harness.counter), [1, 2])
            XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 1)
            harness.stop(self)
        }
    }

    func testAutomaticMTUCacheRefreshesAfterSuccessfulSettingsUpdate() throws {
        let harness = try Harness()
        harness.packetIO.interfaceMTU = 1420
        harness.start(self)
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 1)
        harness.packetIO.interfaceMTU = 1300
        let updated = expectation(description: "updated automatic MTU")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 2)
        harness.drain()
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 2)
        let current = try XCTUnwrap(harness.transports.transports.last)
        current.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([]) // Release the read retained across the configuration generation.
        harness.drain()
        let packet = Harness.packetWithLength(1300)
        harness.packetIO.deliver([packet])
        harness.drain()
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), [packet])
        XCTAssertEqual(current.dataPackets.first?.count, 1300 + 32)
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 2)
    }

    func testAutomaticMTUCacheRefreshesAfterRollbackAndSocketReplacement() throws {
        let harness = try Harness()
        harness.packetIO.interfaceMTU = 1420
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.packetIO.delaySettings = true
        let restored = expectation(description: "automatic MTU after rollback")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNotNil(error)
            restored.fulfill()
        }
        harness.drain()
        let apply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        harness.packetIO.interfaceMTU = 1400 // Automatic settings can resolve to a changed path MTU.
        harness.packetIO.delaySettings = false
        apply(NSError(domain: "test.settings", code: 1))
        wait(for: [restored], timeout: 2)
        harness.drain()
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 2)
        let beforeReplacement = Harness.packetWithLength(1400)
        harness.packetIO.deliver([beforeReplacement])
        harness.drain()
        XCTAssertEqual(old.dataPackets.first?.count, 1400 + 32)
        harness.packetIO.interfaceMTU = 1281
        harness.clock.time = 1001
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1003)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 3)
        let packet = Harness.packetWithLength(1281)
        harness.packetIO.deliver([packet])
        harness.drain()
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), [packet])
        XCTAssertEqual(current.dataPackets.first?.count, 1281 + 32)
        XCTAssertEqual(current.dataPackets.map(Harness.counter), [3], "A changed padding limit must not reset the session nonce")
        XCTAssertEqual(harness.packetIO.interfaceMTUReadCount, 3)
        XCTAssertTrue(harness.packetIO.mainThreadOperations.isEmpty)
    }

    func testInterfaceMTUReadHandlesMissingAndInvalidNames() throws {
        XCTAssertGreaterThan(try XCTUnwrap(NativeWireGuardAdapter.readInterfaceMTU(named: "lo0")), 0)
        XCTAssertNil(NativeWireGuardAdapter.readInterfaceMTU(named: "wg_mtu_missing"))
        XCTAssertNil(NativeWireGuardAdapter.readInterfaceMTU(named: ""))
        XCTAssertNil(NativeWireGuardAdapter.readInterfaceMTU(named: String(repeating: "x", count: 128)))
    }

    func testExplicitNonAlignedMTUCapsPaddingAndRejectsLargerOutboundPackets() throws {
        let configuration = try Harness.configuration()
        configuration.interface.mtu = 1281
        let harness = try Harness(configuration: configuration)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let packet = Harness.packetWithLength(1281)
        harness.packetIO.deliver([packet, Harness.packetWithLength(1282)])
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [packet])
        XCTAssertEqual(transport.dataPackets.first?.count, 1281 + 32)
        harness.packetIO.deliver([packet])
        harness.drain()
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), [1, 2], "An over-MTU packet must not reserve a nonce")
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testAutomaticMTUDeliversLargerAuthenticatedInboundPackets() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let packet = Harness.packetWithLength(1401)
        transport.deliver(try Harness.incoming(counter: 0, packet: packet))
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenPackets, [packet])
    }

    func testFailedSettingsUpdateRestoresThePreviousMTUAndPaddingPolicy() throws {
        let configuration = try Harness.configuration()
        configuration.interface.mtu = 1281
        let harness = try Harness(configuration: configuration)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let replacement = try Harness.configuration()
        replacement.interface.mtu = 1420
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "restore previous MTU after settings failure")
        harness.adapter.update(tunnelConfiguration: replacement, reassert: true) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        let apply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        harness.packetIO.delaySettings = false
        apply(NSError(domain: "test.settings", code: 1))
        wait(for: [completed], timeout: 2)
        harness.drain()
        let restored = try XCTUnwrap(harness.packetIO.settings.last ?? nil)
        XCTAssertEqual(restored.mtu, 1281)
        XCTAssertNil(restored.tunnelOverheadBytes)
        harness.packetIO.deliver([Harness.packetWithLength(1281)])
        harness.drain()
        XCTAssertEqual(transport.dataPackets.first?.count, 1281 + 32)
        XCTAssertFalse(transport.cancelled)
    }

    func testStartWithoutAttachedProviderFails() throws {
        let adapter = NativeWireGuardAdapter()
        let completed = expectation(description: "start rejects missing provider")
        adapter.start(tunnelConfiguration: try Harness.configuration()) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }

    func testStopInvalidatesDelayedSettingsCompletion() throws {
        let harness = try Harness()
        harness.packetIO.delaySettings = true
        let started = expectation(description: "cancelled start completes")
        harness.adapter.start(tunnelConfiguration: harness.configuration) { error in
            XCTAssertNotNil(error)
            started.fulfill()
        }
        harness.drain()
        harness.stop(self)
        wait(for: [started], timeout: 2)
        harness.packetIO.settingsCompletion?(nil)
        harness.drain()
        XCTAssertTrue(harness.transports.transports.isEmpty)
    }

    func testOldReadAfterStopAndStartReleasesOwnershipWithoutForwardingPackets() throws {
        let harness = try Harness()
        harness.start(self)
        let oldRead = try XCTUnwrap(harness.packetIO.readCompletion)
        harness.stop(self)
        harness.start(self)
        XCTAssertEqual(harness.packetIO.readCount, 1)
        oldRead([Harness.packet], [NSNumber(value: AF_INET)])
        harness.drain()
        XCTAssertEqual(harness.packetIO.readCount, 2)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        let transport = try XCTUnwrap(harness.transports.transports.last)
        transport.deliver(Harness.response)
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 4 }.count, 1, "Only the handshake-confirmation keepalive is sent")
    }

    func testUpdateDoesNotCreateASecondPacketReader() throws {
        let harness = try Harness()
        harness.start(self)
        let oldRead = try XCTUnwrap(harness.packetIO.readCompletion)
        let updated = expectation(description: "update")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 2)
        XCTAssertEqual(harness.packetIO.readCount, 1)
        oldRead([], [])
        harness.drain()
        XCTAssertEqual(harness.packetIO.readCount, 2)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        XCTAssertEqual(harness.packetIO.reasserting.last, false)
    }

    func testFailedSettingsUpdateRestoresPreviousSettingsAndKeepsAuthenticatedTraffic() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let replacement = try Harness.configuration()
        replacement.interface.addresses = [try XCTUnwrap(IPAddressRange(from: "10.0.0.7/32"))]
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "failed update restores previous settings")
        harness.adapter.update(tunnelConfiguration: replacement, reassert: true) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        let updateSettings = try XCTUnwrap(harness.packetIO.settings.last ?? nil)
        XCTAssertEqual(updateSettings.ipv4Settings?.addresses, ["10.0.0.7"])
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [Harness.packet])
        let apply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        harness.packetIO.delaySettings = false
        apply(NSError(domain: "test.settings", code: 1))
        wait(for: [completed], timeout: 2)
        harness.drain()
        let restoredSettings = try XCTUnwrap(harness.packetIO.settings.last ?? nil)
        XCTAssertEqual(restoredSettings.ipv4Settings?.addresses, ["10.0.0.1"])
        XCTAssertFalse(transport.cancelled)
        XCTAssertEqual(harness.transports.transports.count, 1)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), [1, 2], "A failed settings update must not replace keys or reuse nonces")
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [Harness.packet, Harness.packet])
        let retried = expectation(description: "a subsequent settings update can succeed")
        harness.adapter.update(tunnelConfiguration: replacement, reassert: true) { error in
            XCTAssertNil(error)
            retried.fulfill()
        }
        wait(for: [retried], timeout: 2)
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertTrue(transport.cancelled)
        XCTAssertEqual(harness.packetIO.reasserting.last, false)
    }

    func testSettingsUpdateTimeoutCancelsProviderWithoutOverlappingSettingsRequests() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "timed out unresolved settings update cancels provider")
        completed.assertForOverFulfill = true
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            guard let error, case .setNetworkSettings = error else {
                XCTFail("The update must report its settings timeout, not generic operation cancellation")
                completed.fulfill()
                return
            }
            completed.fulfill()
        }
        harness.drain()
        let lateApply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        XCTAssertEqual(harness.packetIO.settings.count, 2)
        harness.advance(to: 1015)
        wait(for: [completed], timeout: 2)
        harness.drain()
        XCTAssertTrue(transport.cancelled)
        XCTAssertEqual(harness.packetIO.cancelledErrors.count, 1)
        XCTAssertEqual(harness.packetIO.settings.count, 2, "An unresolved apply must not race a rollback request")
        lateApply(nil)
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 1, "Late success cannot resurrect the cancelled provider")
        XCTAssertEqual(harness.packetIO.settings.count, 2)
        XCTAssertEqual(harness.packetIO.cancelledErrors.count, 1)
        harness.packetIO.delaySettings = false
        harness.start(self)
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
    }

    func testFailedSettingsRestoreCancelsProviderAndAllowsCleanStart() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "failed restore completes update")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        let apply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        apply(NSError(domain: "test.settings", code: 1))
        harness.drain()
        let restore = try XCTUnwrap(harness.packetIO.settingsCompletion)
        restore(NSError(domain: "test.restore", code: 2))
        wait(for: [completed], timeout: 2)
        harness.drain()
        XCTAssertTrue(transport.cancelled)
        XCTAssertEqual(harness.packetIO.cancelledErrors.count, 1)
        harness.packetIO.delaySettings = false
        harness.start(self)
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
    }

    func testSettingsRestoreTimeoutCancelsProviderAndIgnoresLateRestore() throws {
        let harness = try Harness()
        harness.start(self)
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "timed out restore completes update")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        let apply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        apply(NSError(domain: "test.settings", code: 1))
        harness.drain()
        let lateRestore = try XCTUnwrap(harness.packetIO.settingsCompletion)
        harness.advance(to: 1005)
        wait(for: [completed], timeout: 2)
        lateRestore(nil)
        harness.drain()
        XCTAssertEqual(harness.packetIO.cancelledErrors.count, 1)
        XCTAssertTrue(try XCTUnwrap(harness.transports.transports.first).cancelled)
    }

    func testStopCancelsPendingSettingsUpdateOnceAndLateFailureCannotStopNewStart() throws {
        let harness = try Harness()
        harness.start(self)
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "stopping cancels pending update")
        completed.assertForOverFulfill = true
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        let lateApply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        harness.stop(self)
        wait(for: [completed], timeout: 2)
        harness.packetIO.delaySettings = false
        harness.start(self)
        lateApply(NSError(domain: "test.settings", code: 1))
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testOverlappingSettingsUpdateIsRejectedWithoutReplacingPendingUpdate() throws {
        let harness = try Harness()
        harness.start(self)
        harness.packetIO.delaySettings = true
        let first = expectation(description: "first update succeeds")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            first.fulfill()
        }
        harness.drain()
        let apply = try XCTUnwrap(harness.packetIO.settingsCompletion)
        let rejected = expectation(description: "overlapping update rejected")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNotNil(error)
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 2)
        harness.drain()
        XCTAssertEqual(harness.packetIO.settings.count, 2)
        XCTAssertEqual(harness.transports.transports.count, 1)
        apply(nil)
        wait(for: [first], timeout: 2)
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testStoppedReadCallbackDoesNotRearmPump() throws {
        let harness = try Harness()
        harness.start(self)
        let read = try XCTUnwrap(harness.packetIO.readCompletion)
        harness.stop(self)
        read([Harness.packet], [NSNumber(value: AF_INET)])
        harness.drain()
        XCTAssertEqual(harness.packetIO.readCount, 1)
        XCTAssertEqual(harness.transports.transports.first?.cancelled, true)
    }

    func testWaitingThenReadyDoesNotReconnectAtOldDeadline() throws {
        let harness = try Harness()
        harness.transports.autoReady = false
        let started = expectation(description: "socket recovers")
        harness.adapter.start(tunnelConfiguration: harness.configuration) { error in
            XCTAssertNil(error)
            started.fulfill()
        }
        harness.drain()
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.stateChanged?(.waiting(.posix(.ENETDOWN)))
        harness.drain()
        transport.stateChanged?(.ready)
        wait(for: [started], timeout: 2)
        harness.advance(to: 1003)
        XCTAssertEqual(harness.transports.transports.count, 1)
        XCTAssertFalse(transport.cancelled)
    }

    func testInitialSatisfiedPathDoesNotReplaceTheInitialTransport() throws {
        let harness = try Harness()
        harness.start(self)
        var recoveries: [() -> Void] = [] // Accessed only on the adapter's owner queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertTrue(recoveries.isEmpty)
        }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 1)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.first).cancelled)
    }

    func testSatisfiedPathHandoffCallbacksCoalesceWithoutRequiringAnOfflineInterval() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        var recoveries: [() -> Void] = [] // Accessed only on the adapter's owner queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertEqual(recoveries.count, 1)
            XCTAssertFalse(old.cancelled, "Keep the current transport until the coalesced action runs")
            recoveries.removeFirst()()
        }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertTrue(old.cancelled)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        XCTAssertEqual(harness.packetIO.readCount, 1)
        XCTAssertTrue(old.mainThreadOperations.isEmpty)
    }

    func testOfflinePathCancelsPendingHandoffAndOnlinePathResumesOnce() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        var recoveries: [() -> Void] = [] // Accessed only on the adapter's owner queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .unsatisfied)
            XCTAssertEqual(recoveries.count, 1)
            recoveries.removeFirst()()
        }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 1, "The obsolete satisfied action cannot reconnect offline")
        XCTAssertTrue(old.cancelled)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.adapter.queue.sync {
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertEqual(recoveries.count, 1)
            recoveries.removeFirst()()
        }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertEqual(harness.queuedPacketBytes, Harness.packet.count)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testDelayedPathRecoveryDoesNotReplaceATransportAlreadyRecoveredByTheRetryTimer() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.stateChanged?(.waiting(.posix(.ENETDOWN)))
        harness.drain()
        var recoveries: [() -> Void] = [] // Accessed only on the adapter's owner queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertEqual(recoveries.count, 1)
        }
        harness.advance(to: 1003)
        XCTAssertEqual(harness.transports.transports.count, 2)
        harness.adapter.queue.sync { recoveries.removeFirst()() }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2, "An older path callback cannot replace the new transport again")
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
    }

    func testStoppedAdapterRejectsDelayedPathRecovery() throws {
        let harness = try Harness()
        harness.start(self)
        var recoveries: [() -> Void] = [] // Accessed only on the adapter's owner queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertEqual(recoveries.count, 1)
        }
        harness.stop(self)
        harness.adapter.queue.sync { recoveries.removeFirst()() }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 1)
        XCTAssertTrue(try XCTUnwrap(harness.transports.transports.first).cancelled)
    }

    func testUpdatedAdapterRejectsDelayedPathRecoveryFromTheOldGeneration() throws {
        let harness = try Harness()
        harness.start(self)
        var recoveries: [() -> Void] = [] // Accessed only on the adapter's owner queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertEqual(recoveries.count, 1)
        }
        let updated = expectation(description: "update before delayed handoff")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 2)
        harness.adapter.queue.sync { recoveries.removeFirst()() }
        harness.drain()
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testSocketReplacementPreservesKeysNoncesAndReceiveReplayHistory() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        old.deliver(Harness.receivedTransport)
        harness.drain()
        let staleReceive = try XCTUnwrap(old.received)
        harness.clock.time = 1001
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1003)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertFalse(old === current)
        XCTAssertTrue(old.cancelled)
        XCTAssertEqual(current.sent.map { $0.first }, [4], "A live peer confirms the new path without another handshake")
        XCTAssertEqual(Harness.counter(try XCTUnwrap(current.sent.first)), 2)
        harness.packetIO.deliver([Harness.packet])
        current.deliver(Harness.receivedTransport)
        harness.drain()
        XCTAssertEqual(current.dataPackets.map(Harness.counter), [3])
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), [Harness.packet])
        XCTAssertEqual(harness.packetIO.writtenPackets.count, 1, "The old receive replay history survives a socket replacement")
        current.deliver(try Harness.incoming(counter: 1, packet: Harness.packet))
        staleReceive([], .posix(.ENETDOWN))
        harness.drain()
        harness.advance(to: 1006)
        XCTAssertEqual(harness.packetIO.writtenPackets.count, 2)
        XCTAssertEqual(harness.transports.transports.count, 2, "Old receive failures must not replace the new socket")
        XCTAssertFalse(current.cancelled)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testOfflinePathRecoveryKeepsTheAuthenticatedPeerAndBufferedTraffic() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        var recoveries: [() -> Void] = [] // Owned by the adapter queue.
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { recoveries.append($0) }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .unsatisfied)
        }
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertTrue(old.cancelled)
        XCTAssertEqual(harness.queuedPacketBytes, Harness.packet.count)
        harness.adapter.queue.sync {
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            XCTAssertEqual(recoveries.count, 1)
            recoveries.removeFirst()()
        }
        harness.drain()
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertEqual(current.sent.map { $0.first }, [4, 4])
        XCTAssertEqual(current.sent.map(Harness.counter), [1, 2])
        XCTAssertEqual(current.sent.first?.count, 32, "Path confirmation precedes buffered IP data")
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), [Harness.packet])
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testSocketReplacementWaitsForAnOutstandingHandshakeRetryDeadline() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        harness.clock.time = 1001
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1003)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertTrue(current.sent.isEmpty, "Rebinding must not bypass the outstanding five-second retry spacing")
        harness.advance(to: 1004.9)
        XCTAssertTrue(current.sent.isEmpty)
        harness.advance(to: 1005)
        XCTAssertEqual(current.sent.map { $0.first }, [1])
        XCTAssertEqual(old.sent.count, 1)
    }

    func testSocketReplacementStartsANewHandshakeWhenTheSessionHasExpired() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.clock.time = 1180
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1182)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertEqual(current.sent.map { $0.first }, [1])
        XCTAssertTrue(current.dataPackets.isEmpty)
        XCTAssertEqual(current.sent.first?.count, 148)
    }

    func testSocketReplacementDiscardsOldCryptoResultsWithoutReusingReservedNonces() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 8))
        harness.drain()
        let oldWork = harness.takeEncryptionJobs()
        XCTAssertEqual(oldWork.count, 1)
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1002)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertEqual(current.sent.map(Harness.counter), [9], "Discarded crypto reservations remain consumed")
        harness.completeEncryptionJobs(oldWork)
        XCTAssertTrue(current.dataPackets.isEmpty)
        harness.holdEncryption = false
        harness.drain()
        XCTAssertEqual(current.dataPackets.map(Harness.counter), Array(UInt64(10)...17))
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), Array(repeating: Harness.packet, count: 8))
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testSocketReplacementPreservesPreviousReceiveSessionDuringRekeyOverlap() throws {
        let harness = try Harness(freshRekeyKeys: true)
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.advance(to: 1120)
        old.deliver(Harness.rekeyResponse)
        harness.drain()
        old.deliver(Harness.receivedTransport)
        harness.drain()
        harness.clock.time = 1121
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1123)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertEqual(current.sent.map { $0.first }, [4])
        XCTAssertEqual(current.sent.map(Harness.counter), [1], "The current key's send counter survives replacement")
        current.deliver(try Harness.incoming(counter: 1, packet: Harness.packet))
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenPackets, [Harness.packet, Harness.packet])
    }

    func testSocketReplacementConfirmsTheLivePathBeforeRequestingAnAgeBasedRekey() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1122)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertFalse(current === old)
        XCTAssertEqual(Array(current.sent.prefix(2)).map { $0.first }, [4, 1])
        XCTAssertEqual(current.sent.first?.count, 32)
        XCTAssertEqual(Harness.counter(try XCTUnwrap(current.sent.first)), 1,
                       "The path-confirmation keepalive continues the current session's nonce counter")
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testSocketReplacementPreservesAnUnsubmittedRekeyInitiationAndControlPriority() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        old.automaticallyCompleteSends = false
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        harness.advance(to: 1025)
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        harness.packetIO.deliver([Harness.packet]) // Request the rekey through fresh outbound traffic.
        harness.drain()
        harness.advance(to: 1120)
        XCTAssertEqual(old.sent.filter { $0.first == 1 }.count, 1, "Rekey is queued behind the saturated control slot")
        let staleSend = try XCTUnwrap(old.pendingSends.first)
        old.stateChanged?(.failed(.posix(.ENETDOWN)))
        harness.drain()
        harness.advance(to: 1122)
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertEqual(Array(current.sent.prefix(2)).map { $0.first }, [4, 1])
        XCTAssertEqual(current.sent.first?.count, 32)
        XCTAssertEqual(current.dataPackets.count, 66, "Only unsent plaintext is moved to the new socket")
        staleSend(.posix(.ENETDOWN))
        harness.drain()
        harness.advance(to: 1126)
        XCTAssertEqual(current.sent.filter { $0.first == 1 }.count, 1, "Retry spacing starts when the preserved initiation is actually submitted")
        XCTAssertEqual(harness.transports.transports.count, 2)
        harness.advance(to: 1127)
        XCTAssertEqual(current.sent.filter { $0.first == 1 }.count, 2)
        XCTAssertFalse(current.cancelled)
    }

    func testRetryBudgetCountsTransmissionsAndLeavesTheTunnelAvailableAfterExhaustion() throws {
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive())
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.advance(to: 1004.9)
        XCTAssertEqual(transport.sent.count, 1)
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        harness.advance(to: 1100)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
        XCTAssertEqual(harness.queuedPacketBytes, 0, "The exhausted episode flushes traffic staged without usable keys")
        XCTAssertEqual(harness.packetIO.pendingReads, 1)
        harness.advance(to: 1200)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20, "Idle timer checks must not start another retry episode")
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testFreshTrafficRefreshesAnActiveHandshakeBudgetWithoutSendingBeforeTheRetryDeadline() throws {
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive())
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        for retry in 1...18 { harness.advance(to: 1000 + Double(retry) * 5) }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 19)
        for request in 0..<4 {
            harness.advance(to: 1092 + Double(request) * 5)
            let sent = transport.sent.filter { $0.first == 1 }.count
            harness.packetIO.deliver([Harness.packet])
            harness.drain()
            XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, sent,
                           "Fresh requests refresh the budget but retain the outstanding five-second retry deadline")
            harness.advance(to: 1095 + Double(request) * 5)
            XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, sent + 1)
        }
        // The last fresh request was at1107, with its first retry at1110. Nineteen
        // retries after that request remain available; the existing backlog is not fresh activity.
        for retry in 1...18 { harness.advance(to: 1110 + Double(retry) * 5) }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 41)
        XCTAssertEqual(harness.queuedPacketBytes, 4 * Harness.packet.count)
        harness.advance(to: 1205)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 41)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        harness.advance(to: 1300)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 41)
        XCTAssertFalse(transport.cancelled)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testQueuedBacklogWithoutNewRequestsDoesNotRefreshTheHandshakeBudget() throws {
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive())
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 1_000))
        harness.drain()
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        XCTAssertEqual(harness.queuedPacketBytes, 1_000 * Harness.packet.count)
        harness.advance(to: 1100)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testFreshTrafficWithAnUnsubmittedInitiationStartsItsBudgetAtActualSubmission() throws {
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive())
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.advance(to: 1120)
        harness.packetIO.deliver([Harness.packet]) // Fresh demand starts the age-based rekey.
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        for retry in 1...8 { harness.advance(to: 1120 + Double(retry) * 5) }
        transport.automaticallyCompleteSends = false
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 63))
        harness.drain()
        XCTAssertEqual(transport.pendingSends.count, 63)
        harness.advance(to: 1165)
        XCTAssertEqual(transport.pendingSends.count, 64)
        harness.advance(to: 1170)
        let sent = transport.sent.filter { $0.first == 1 }.count
        harness.adapter.queue.sync { harness.clock.time = 1181 }
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, sent,
                       "Fresh traffic must not bypass the full transport or replace an unsent initiation")
        transport.automaticallyCompleteSends = true
        transport.pendingSends.removeLast()(nil) // Release the control slot occupied by the1165 initiation.
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, sent + 1)
        for retry in 1...19 { harness.advance(to: 1181 + Double(retry) * 5) }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, sent + 20,
                       "The pending initiation becomes the first counted transmission only when submitted")
        XCTAssertEqual(harness.queuedPacketBytes, Harness.packet.count)
        harness.advance(to: 1281)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, sent + 20)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        XCTAssertFalse(transport.cancelled)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testConfiguredKeepaliveRearmsExhaustedHandshakeOnlyAtItsDeadline() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        harness.advance(to: 1100)
        harness.advance(to: 1119.9)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        harness.advance(to: 1120) // Twenty-five seconds after the final initiation at1095.
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 21)
        harness.advance(to: 1120.5)
        harness.advance(to: 1124.9)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 21, "One configured keepalive event starts one episode")
        harness.advance(to: 1125)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 22)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
    }

    func testFreshTrafficAfterExhaustionStartsANewAttemptAndAuthenticates() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        harness.advance(to: 1100)
        let previous = try XCTUnwrap(transport.sent.last { $0.first == 1 })
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        let initiation = try XCTUnwrap(transport.sent.last { $0.first == 1 })
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 21)
        XCTAssertNotEqual(initiation[4..<8], previous[4..<8], "A fresh attempt cannot reuse the prior sender index")
        transport.deliver(try Harness.response(to: initiation, configuration: harness.configuration))
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [Harness.packet], "Only fresh traffic survives the old episode")
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), [1])
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testLateResponseCanCompleteTheLastExhaustedAttempt() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        let lastInitiation = try XCTUnwrap(transport.sent.last { $0.first == 1 })
        harness.advance(to: 1100)
        transport.deliver(try Harness.response(to: lastInitiation, configuration: harness.configuration))
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [Harness.packet])
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testFreshTrafficStartsAnExchangeWhenOnlyUnconfirmedResponderKeysAreAvailable() throws {
        let harness = try Harness(responderFixture: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.initiation)
        harness.drain()
        transport.deliver(Harness.sentTransport)
        harness.drain()
        harness.adapter.queue.sync { harness.clock.time = 1200 }
        transport.deliver(Harness.rekeyInitiation)
        harness.drain()
        let attempts = transport.sent.filter { $0.first == 1 }.count
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, attempts,
                       "Fresh traffic must still respect the five-second guard after a response")
        harness.advance(to: 1205)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, attempts + 1,
                       "New outbound traffic starts an exchange as soon as the response guard expires")
        XCTAssertTrue(transport.dataPackets.isEmpty, "Unconfirmed response keys remain unusable for sending")
        XCTAssertEqual(harness.queuedPacketBytes, Harness.packet.count)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testOfflineQueuedTrafficStartsAnExchangeAfterRecoveringWithUnconfirmedResponderKeys() throws {
        let harness = try Harness(responderFixture: true)
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.initiation)
        harness.drain()
        old.deliver(Harness.sentTransport)
        harness.drain()
        harness.adapter.queue.sync { harness.clock.time = 1200 }
        old.deliver(Harness.rekeyInitiation)
        harness.drain()
        harness.adapter.queue.sync { harness.adapter.handleNetworkPathUpdate(status: .unsatisfied) }
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(harness.queuedPacketBytes, Harness.packet.count)
        harness.adapter.queue.sync {
            // The response's five-second initiation guard has elapsed while offline.
            harness.clock.time = 1206
            harness.adapter.schedulePathRecovery = { $0() }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
        }
        harness.drain()
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertFalse(current === old)
        XCTAssertTrue(old.cancelled)
        XCTAssertEqual(current.sent.filter { $0.first == 1 }.count, 1,
                       "Queued offline traffic must initiate instead of waiting for unconfirmed responder keys")
        XCTAssertTrue(current.dataPackets.isEmpty)
        XCTAssertEqual(harness.queuedPacketBytes, Harness.packet.count)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testExhaustedPartialHandshakeExpiresWithoutStoppingTheTunnel() throws {
        var observedPeer: WireGuardPeer? // Created and inspected only on the adapter's owner queue.
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive(), observePeer: { observedPeer = $0 })
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        let lastInitiation = try XCTUnwrap(transport.sent.last { $0.first == 1 })
        let lateResponse = try Harness.response(to: lastInitiation, configuration: harness.configuration)
        harness.advance(to: 1100)
        harness.advance(to: 1639)
        try harness.adapter.queue.sync {
            XCTAssertThrowsError(try XCTUnwrap(observedPeer).receive(lateResponse)) { error in
                XCTAssertEqual(error as? WireGuardPeer.Error, .handshakeExpired)
            }
        }
        harness.advance(to: 1640) // Five hundred forty seconds after retry exhaustion.
        try harness.adapter.queue.sync {
            XCTAssertThrowsError(try XCTUnwrap(observedPeer).receive(lateResponse)) { error in
                XCTAssertEqual(error as? WireGuardPeer.Error, .handshakeRequired, "Expired partial exchange is discarded, not merely unusable")
            }
        }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 21)
    }

    func testLongSleepWithAPendingHandshakeConsumesOnlyOneRetryAfterWake() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        harness.advance(to: 1600)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
        harness.advance(to: 1604.9)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        harness.advance(to: 1605)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 3)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testExhaustedRekeyPreservesLiveSessionAndItsNonceCounter() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.advance(to: 1015) // Unanswered data starts a new attempt while the current key is live.
        for retry in 1...19 { harness.advance(to: 1015 + Double(retry) * 5) }
        harness.advance(to: 1115)
        let initiations = transport.sent.filter { $0.first == 1 }.count
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), [Harness.packet, Harness.packet])
        XCTAssertGreaterThan(Harness.counter(try XCTUnwrap(transport.dataPackets.last)),
                             Harness.counter(try XCTUnwrap(transport.dataPackets.first)))
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, initiations)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
    }

    func testFreshDataAfterExhaustionArmsAnUnansweredHandshakeWithItsOwnRetryBudget() throws {
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive(), recordProtocolTimers: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.advance(to: 1015)
        for retry in 1...19 { harness.advance(to: 1015 + Double(retry) * 5) }
        harness.advance(to: 1115)
        harness.advance(to: 1116)
        let initiations = transport.sent.filter { $0.first == 1 }.count
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, initiations,
                       "A fresh packet using live116-second-old keys does not itself request a rekey")
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1131, accuracy: 0.000_001,
                       "The fresh authenticated send must still arm its unanswered-data timeout")
        harness.fireProtocolTimer(at: 1131)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, initiations + 1)
        for retry in 1...19 { harness.advance(to: 1131 + Double(retry) * 5) }
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, initiations + 20,
                       "The unanswered-data event gets a fresh complete retry episode")
        harness.advance(to: 1231)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, initiations + 20)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
    }

    func testConfiguredKeepaliveRearmsAnExhaustedRekeyWithLiveKeys() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.advance(to: 1015)
        for retry in 1...19 { harness.advance(to: 1015 + Double(retry) * 5) }
        harness.advance(to: 1115)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 21)
        harness.advance(to: 1135) // A keepalive using live135-second-old keys also requests a rekey.
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 22)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
    }

    func testNetworkRecoveryRearmsAnExhaustedRekeyWithLiveKeys() throws {
        let harness = try Harness(configuration: Harness.configurationWithoutPersistentKeepalive())
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.advance(to: 1015)
        for retry in 1...19 { harness.advance(to: 1015 + Double(retry) * 5) }
        harness.advance(to: 1115)
        harness.advance(to: 1121)
        XCTAssertEqual(old.sent.filter { $0.first == 1 }.count, 21, "The exhausted idle episode stays stopped")
        harness.adapter.queue.sync {
            harness.adapter.schedulePathRecovery = { $0() }
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
            harness.adapter.handleNetworkPathUpdate(status: .satisfied)
        }
        harness.drain()
        let current = try XCTUnwrap(harness.transports.transports.last)
        XCTAssertFalse(current === old)
        XCTAssertEqual(current.sent.filter { $0.first == 1 }.count, 1, "A fresh path permits another rekey episode")
        XCTAssertTrue(current.sent.contains { $0.first == 4 && $0.count == 32 }, "Live keys confirm the new path without being discarded")
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
    }

    func testExhaustionDiscardsUnusableCryptoAndLateWorkersCannotSendOldTraffic() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.advance(to: 1120)
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 64))
        harness.drain()
        XCTAssertGreaterThan(harness.scheduledEncryptionCount, 0)
        for retry in 1...19 { harness.advance(to: 1120 + Double(retry) * 5) }
        harness.advance(to: 1220)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        harness.holdEncryption = false
        harness.drain()
        XCTAssertTrue(transport.dataPackets.isEmpty)
        XCTAssertTrue(harness.packetIO.cancelledErrors.isEmpty)
        XCTAssertFalse(transport.cancelled)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testFractionalHandshakeJitterUsesItsActualDeadline() throws {
        let harness = try Harness(recordProtocolTimers: true, retryJitter: { 0.2 })
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1005.2, accuracy: 0.000_001)
        harness.advance(to: 1005.19)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1)
        harness.fireProtocolTimer(at: 1005.2)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1010.4, accuracy: 0.000_001)
    }

    func testUnansweredDataUsesOneRecordedFractionalDeadlineWithoutRedrawingJitter() throws {
        let configuration = try Harness.configuration(persistentKeepAlive: 0)
        var jitterDraws = 0 // Accessed on the adapter queue, except after queue synchronization.
        let harness = try Harness(configuration: configuration, recordProtocolTimers: true, retryJitter: {
            jitterDraws += 1
            return 0.2
        })
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.adapter.queue.sync { harness.clock.time = 1001 }
        let drawsBeforeData = harness.adapter.queue.sync { jitterDraws }
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1016.2, accuracy: 0.000_001)
        XCTAssertEqual(harness.adapter.queue.sync { jitterDraws }, drawsBeforeData + 1)
        harness.adapter.queue.sync {
            harness.clock.time = 1002
            for _ in 0..<10 { _ = harness.adapter.nextProtocolDeadline() }
        }
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1016.2, accuracy: 0.000_001,
                       "More outgoing data does not postpone the first unanswered packet's deadline")
        XCTAssertEqual(harness.adapter.queue.sync { jitterDraws }, drawsBeforeData + 1,
                       "Deadline calculations and subsequent packets must not redraw jitter")
        harness.advance(to: 1016.19)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1)
        harness.fireProtocolTimer(at: 1016.2)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1021.4, accuracy: 0.000_001)
    }

    func testOldProtocolTimerCannotDriveAReplacementAdapterGeneration() throws {
        let harness = try Harness(recordProtocolTimers: true)
        harness.start(self)
        let stale = try XCTUnwrap(harness.protocolTimerCallback)
        harness.stop(self)
        harness.start(self)
        let current = try XCTUnwrap(harness.transports.transports.last)
        harness.adapter.queue.sync {
            harness.clock.time = 1006
            stale()
        }
        harness.drain()
        XCTAssertEqual(current.sent.filter { $0.first == 1 }.count, 1, "A cancelled generation cannot fire the new generation's due timer")
        XCTAssertEqual(harness.protocolDeadline, 1005)
    }

    func testBlockedControlUsesCompletionsInsteadOfAnExpiredTimerLoop() throws {
        let harness = try Harness(recordProtocolTimers: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        transport.automaticallyCompleteSends = false
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        harness.advance(to: 1025)
        XCTAssertEqual(transport.pendingSends.count, 64)
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1, "The initiation waits for the occupied control slot")
        XCTAssertEqual(harness.protocolDeadline, 1540, "An unsent initiation and in-flight keepalive must not spin on past deadlines")
        transport.pendingSends.removeLast()(nil)
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        XCTAssertEqual(harness.protocolDeadline, 1125, "Actual submission rearms the exact handshake retry deadline")
    }

    func testIdleSessionHasNoPeriodic120SecondRekeyButFreshSendingDoes() throws {
        let configuration = try Harness.configuration(persistentKeepAlive: 0)
        let harness = try Harness(configuration: configuration, recordProtocolTimers: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        XCTAssertEqual(harness.protocolDeadline, 1540, "An idle session only needs eventual key cleanup")
        harness.advance(to: 1120)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2, "Sending with initiator keys aged120s triggers rekey")
        XCTAssertEqual(harness.protocolDeadline, 1125)
    }

    func testExpiredPreparedWorkRequestsKeysWhenItsWorkerCompletes() throws {
        let configuration = try Harness.configuration(persistentKeepAlive: 0)
        let harness = try Harness(configuration: configuration, recordProtocolTimers: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 32))
        harness.drain()
        harness.adapter.queue.sync { harness.clock.time = 1180 }
        harness.holdEncryption = false
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        XCTAssertTrue(transport.dataPackets.isEmpty, "Worker completion must not submit expired ciphertext")
        XCTAssertEqual(harness.protocolDeadline, 1185)
    }

    func testAuthenticatedReceivingRekeysInitiatorOnlyAfter165Seconds() throws {
        let configuration = try Harness.configuration(persistentKeepAlive: 0)
        let harness = try Harness(configuration: configuration)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        for (counter, time) in [(UInt64(0), 1164.9), (1, 1165.0), (2, 1165.01), (3, 1165.02)] {
            harness.adapter.queue.sync { harness.clock.time = time }
            transport.deliver(try Harness.incoming(counter: counter, packet: Harness.packet))
            harness.drain()
            XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, time > 1165 ? 2 : 1)
        }
        XCTAssertEqual(harness.packetIO.writtenPackets.count, 4)
    }

    func testAuthenticatedReceivingDoesNotTimeRekeyAResponderSession() throws {
        let configuration = try Harness.configuration(responder: true, persistentKeepAlive: 0)
        let harness = try Harness(configuration: configuration, responderFixture: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.initiation)
        harness.drain()
        transport.deliver(Harness.sentTransport)
        harness.drain()
        harness.advance(to: 1166)
        let counter: UInt64 = 1
        let header = Data(hex: "0400000008070605") + withUnsafeBytes(of: counter.littleEndian) { Data($0) }
        let key = Data(hex: "e07b709efbfd0361a08a9de658ceb3847d648c207ed71d4dbdfe248bef23a651")
        let plaintext = Harness.packet + Data(repeating: 0, count: 12)
        let incoming = header + (try WireGuardCrypto.seal(key: key, counter: counter, plaintext: plaintext))
        transport.deliver(incoming)
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1, "Responder traffic does not inherit initiator time-based rekeying")
        XCTAssertEqual(harness.packetIO.writtenPackets.count, 2)
    }

    func testConfiguredKeepaliveIsScheduledAfterExhaustionWithoutSessionKeys() throws {
        let harness = try Harness(recordProtocolTimers: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        for retry in 1...19 { harness.advance(to: 1000 + Double(retry) * 5) }
        harness.advance(to: 1100)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 20)
        XCTAssertEqual(harness.protocolDeadline, 1120, "Configured25skeepalive survives retry exhaustion with no keys")
        harness.fireProtocolTimer(at: 1120)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 21)
        XCTAssertEqual(harness.protocolDeadline, 1125)
    }

    func testSettingsRestoreDeadlineUsesTheFractionalCompletionTime() throws {
        let configuration = try Harness.configuration(persistentKeepAlive: 0)
        let harness = try Harness(configuration: configuration, recordProtocolTimers: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "restore deadline cancels the provider")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        XCTAssertEqual(harness.protocolDeadline, 1015)
        harness.adapter.queue.sync { harness.clock.time = 1000.25 }
        harness.packetIO.settingsCompletion?(NSError(domain: "test.settings", code: 1))
        harness.drain()
        XCTAssertEqual(harness.protocolDeadline ?? 0, 1005.25, accuracy: 0.000_001)
        harness.fireProtocolTimer(at: 1005.25)
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(harness.packetIO.cancelledErrors.count, 1)
        XCTAssertNil(harness.protocolDeadline)
    }

    func testUnfinishedNetworkSetupTimesOut() throws {
        let harness = try Harness()
        harness.packetIO.delaySettings = true
        let completed = expectation(description: "startup timeout")
        harness.adapter.start(tunnelConfiguration: harness.configuration) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }
        harness.drain()
        harness.advance(to: 1015)
        wait(for: [completed], timeout: 2)
        harness.packetIO.settingsCompletion?(nil)
        harness.drain()
        XCTAssertTrue(harness.transports.transports.isEmpty)
    }

    func testPendingPacketsAndInflightSendsAreBounded() throws {
        let harness = try Harness(maximumQueuedBytes: 128 * Harness.packet.count)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 1000))
        harness.drain()
        XCTAssertEqual(transport.sent.count, 1, "Data waits for an authenticated session")
        XCTAssertEqual(harness.droppedPacketCount, 872)
        XCTAssertEqual(harness.queuedPacketBytes, 2_560)
        XCTAssertNotNil(harness.packetIO.readCompletion, "Reaching the byte budget must not pause packet-flow reads")
        transport.automaticallyCompleteSends = false
        transport.deliver(Harness.response)
        harness.drain()
        XCTAssertEqual(transport.pendingSends.count, 64)
        while !transport.pendingSends.isEmpty {
            transport.completeSends()
            harness.drain()
        }
        XCTAssertEqual(transport.sent.filter { $0.first == 4 }.count, 129, "128 bounded packets plus one confirmation")
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testHandshakeTimestampAndCountersReflectAuthenticatedTraffic() async throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let handshake = try await harness.adapter.getMostRecentHandshake()
        XCTAssertEqual(handshake, 1_700_000_000)
        transport.deliver(Harness.receivedTransport)
        harness.drain()
        let bytes = try await harness.adapter.getBytesTransmitted()
        XCTAssertEqual(bytes.tx, 32)
        XCTAssertEqual(bytes.rx, UInt64(Harness.receivedTransport.count))
        XCTAssertEqual(harness.packetIO.writtenPackets, [Harness.packet])
        transport.deliver(Harness.receivedTransport)
        harness.drain()
        let afterReplay = try await harness.adapter.getBytesTransmitted()
        XCTAssertEqual(afterReplay.rx, bytes.rx, "Replays do not increase the byte count")
        XCTAssertTrue(harness.packetIO.mainThreadOperations.isEmpty)
        XCTAssertTrue(transport.mainThreadOperations.isEmpty)
    }

    func testSaturatedDataPreservesAControlSlotAndPrioritizesNewSessionConfirmation() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        transport.automaticallyCompleteSends = false
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        XCTAssertEqual(transport.pendingSends.count, 63, "Data leaves one control slot available")
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        harness.packetIO.deliver([Harness.packet]) // Fresh traffic requests the120-second rekey.
        harness.drain()
        harness.advance(to: 1120)
        XCTAssertEqual(transport.pendingSends.count, 64)
        XCTAssertEqual(transport.sent.last?.first, 1, "The rekey initiation uses the reserved slot")

        // The deterministic test peer uses the reference ephemeral key. Reuse its response
        // transcript with the new receiver index and a matching MAC to test adapter scheduling.
        var response = Harness.response
        response.replaceSubrange(8..<12, with: [UInt8(5), 3, 2, 1])
        let macKey = WireGuardCrypto.hash(Data("mac1----".utf8) + harness.configuration.interface.privateKey.publicKey.rawValue)
        response.replaceSubrange(60..<76, with: WireGuardCrypto.mac(key: macKey, data: response.prefix(60)))
        transport.deliver(response)
        harness.drain()
        let count = transport.sent.count
        XCTAssertEqual(transport.pendingSends.count, 64)
        let firstCompleted = transport.pendingSends.removeFirst()
        firstCompleted(nil)
        harness.drain()
        XCTAssertEqual(transport.sent.count, count + 1)
        XCTAssertEqual(transport.sent.last?.count, 32, "The pending confirmation precedes queued data")
    }

    func testStaleSendFailureCannotRestartUpdatedTransport() throws {
        let harness = try Harness()
        harness.start(self)
        let oldTransport = try XCTUnwrap(harness.transports.transports.first)
        oldTransport.deliver(Harness.response)
        harness.drain()
        oldTransport.automaticallyCompleteSends = false
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        let oldSend = try XCTUnwrap(oldTransport.pendingSends.first)
        let updated = expectation(description: "update transport")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 2)
        oldSend(.posix(.ENETDOWN))
        harness.advance(to: 1003)
        XCTAssertEqual(harness.transports.transports.count, 2)
        XCTAssertFalse(try XCTUnwrap(harness.transports.transports.last).cancelled)
    }

    func testQueuedHandshakeRetryIsSpacedFromItsActualSend() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        transport.automaticallyCompleteSends = false
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        harness.advance(to: 1025)
        XCTAssertEqual(transport.pendingSends.count, 64, "A keepalive occupies the remaining control slot")
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        harness.packetIO.deliver([Harness.packet]) // Fresh traffic requests the120-second rekey.
        harness.drain()
        harness.advance(to: 1120)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1, "The new initiation is waiting for capacity")

        harness.clock.time = 1124
        transport.pendingSends.removeLast()(nil)
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        harness.clock.time = 1124.1
        transport.pendingSends.removeLast()(nil)
        harness.drain()
        harness.advance(to: 1125)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2)
        harness.advance(to: 1129)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 3)
    }

    func testPassiveKeepaliveDeadlineIsNotPostponedByMoreIncomingData() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        transport.deliver(Harness.receivedTransport)
        harness.drain()
        harness.clock.time = 1009
        let key = Data(hex: "f76ba55a113d83abf16240859ca361a9017ae9fbac0b4aa43179112c40e0163f")
        let second = Data([4, 0, 0, 0, 4, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0])
            + (try WireGuardCrypto.seal(key: key, counter: 1, plaintext: Harness.packet + Data(repeating: 0, count: 12)))
        transport.deliver(second)
        harness.drain()
        XCTAssertEqual(transport.sent.filter { $0.first == 4 }.count, 1)
        harness.advance(to: 1010)
        XCTAssertEqual(transport.sent.filter { $0.first == 4 }.count, 2)
    }

    func testAllowedIPPolicyChecksInboundSourceAndOutboundDestination() throws {
        let range = try XCTUnwrap(IPAddressRange(from: "10.0.0.1/32"))
        XCTAssertTrue(NativeWireGuardAdapter.permits(Harness.packet, source: true, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(Harness.packet, source: false, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(Data([0x45]), source: true, ranges: [range]))
        XCTAssertFalse(NativeWireGuardAdapter.permits(Harness.packet, source: true, ranges: []))
    }

    func testReverseWorkerCompletionPreservesPacketAndNonceOrder() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        let packets = (UInt8(0)..<96).map { index -> Data in
            var packet = Harness.packet
            packet[4] = index
            return packet
        }
        harness.packetIO.deliver(packets)
        harness.drain()
        let workers = harness.scheduledEncryptionCount
        XCTAssertGreaterThan(workers, 0)
        XCTAssertLessThanOrEqual(workers, 8)
        for index in 0..<workers {
            harness.completeLastEncryptionJob()
            if index < workers - 1 {
                XCTAssertTrue(transport.dataPackets.isEmpty, "Later chunks wait for the earlier reserved packets")
            }
        }
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), Array(UInt64(1)...96))
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), packets)
        XCTAssertTrue(transport.mainThreadOperations.isEmpty)
    }

    func testHeldEncryptionKeepsOwnerResponsiveAndBoundsPacketsWhileControlCanSend() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        XCTAssertGreaterThan(harness.scheduledEncryptionCount, 0)
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 1000))
        harness.drain()
        XCTAssertLessThanOrEqual(harness.scheduledEncryptionCount, 8)
        let observed = expectation(description: "owner responds while crypto is held")
        harness.adapter.getRuntimeConfiguration { configuration in
            XCTAssertNotNil(configuration)
            observed.fulfill()
        }
        wait(for: [observed], timeout: 2)
        transport.deliver(Harness.receivedTransport)
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenPackets, [Harness.packet])
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        harness.packetIO.deliver([Harness.packet]) // Fresh traffic requests the120-second rekey.
        harness.drain()
        harness.advance(to: 1120)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2, "Rekey control is not blocked by crypto workers")
        harness.holdEncryption = false
        harness.drain()
        XCTAssertEqual(transport.dataPackets.count, 1_129, "The default byte budget retains the complete ordinary burst")
        XCTAssertEqual(harness.droppedPacketCount, 0)
    }

    func testStopCompletesWhileEncryptionIsHeldAndDropsLateResults() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 8))
        harness.drain()
        XCTAssertGreaterThan(harness.scheduledEncryptionCount, 0)
        harness.stop(self)
        harness.holdEncryption = false
        harness.drain()
        XCTAssertTrue(transport.cancelled)
        XCTAssertTrue(transport.dataPackets.isEmpty)
        XCTAssertEqual(harness.transports.transports.count, 1)
    }

    func testReadyPrefixIsSentWhileLaterEncryptionGroupsAreStillHeld() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        let packets = (UInt8(0)..<128).map { index -> Data in
            var packet = Harness.packet
            packet[4] = index
            return packet
        }
        harness.packetIO.deliver(packets)
        harness.drain()
        XCTAssertEqual(harness.scheduledEncryptionCount, 4)
        harness.completeFirstEncryptionJob()
        XCTAssertEqual(harness.scheduledEncryptionCount, 3)
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), Array(UInt64(1)...32))
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), Array(packets.prefix(32)))
        harness.completeLastEncryptionJob()
        XCTAssertEqual(transport.dataPackets.count, 32, "A later completed group cannot overtake the next group")
        harness.holdEncryption = false
        harness.drain()
        XCTAssertEqual(try transport.dataPackets.map(Harness.decrypt), packets)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testEncryptionWindowCanProgressWhileAllDataSendSlotsAreFull() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        transport.automaticallyCompleteSends = false
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 320))
        harness.drain()
        XCTAssertEqual(harness.scheduledEncryptionCount, 8)
        harness.completeFirstEncryptionJob()
        harness.completeFirstEncryptionJob()
        XCTAssertEqual(transport.dataPackets.count, 63)
        XCTAssertEqual(transport.pendingSends.count, 63)
        let queuedBytes = harness.queuedPacketBytes
        let jobs = harness.scheduledEncryptionCount
        XCTAssertGreaterThan(jobs, 0)
        harness.completeLastEncryptionJob()
        XCTAssertEqual(harness.scheduledEncryptionCount, jobs - 1)
        XCTAssertEqual(harness.queuedPacketBytes, queuedBytes, "Crypto completion retains the budget until UDP submission")
        XCTAssertEqual(transport.dataPackets.count, 63)
        XCTAssertNotNil(harness.packetIO.readCompletion)
        harness.holdEncryption = false
        harness.drain()
        while !transport.pendingSends.isEmpty {
            transport.completeSends()
            harness.drain()
        }
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), Array(UInt64(1)...320))
        XCTAssertEqual(harness.droppedPacketCount, 0)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testDefaultBudgetAcceptsLargeBurstsAndKeepsOnePacketReader() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 8_192))
        harness.drain()
        XCTAssertEqual(harness.queuedPacketBytes, 8_192 * Harness.packet.count)
        XCTAssertEqual(harness.droppedPacketCount, 0)
        XCTAssertEqual(harness.packetIO.pendingReads, 1)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        transport.deliver(Harness.response)
        harness.drain()
        XCTAssertEqual(transport.dataPackets.count, 8_192)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        XCTAssertEqual(harness.droppedPacketCount, 0)
        XCTAssertEqual(harness.packetIO.pendingReads, 1)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
    }

    func testByteBudgetCoversPendingCryptoAndReadyDataAndIsReleasedOnSend() throws {
        let harness = try Harness(maximumQueuedBytes: 128 * Harness.packet.count)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        XCTAssertEqual(harness.queuedPacketBytes, 2_560)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertEqual(harness.droppedPacketCount, 1)
        XCTAssertEqual(harness.queuedPacketBytes, 2_560)
        harness.completeLastEncryptionJob()
        XCTAssertEqual(harness.queuedPacketBytes, 2_560, "Out-of-order ready data is still retained in memory")
        harness.completeFirstEncryptionJob()
        XCTAssertEqual(harness.queuedPacketBytes, 96 * Harness.packet.count)
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 32))
        harness.drain()
        XCTAssertEqual(harness.queuedPacketBytes, 2_560)
        XCTAssertEqual(harness.droppedPacketCount, 1)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        harness.holdEncryption = false
        harness.drain()
        XCTAssertEqual(transport.dataPackets.count, 160)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
    }

    func testRealWorkerPoolDrainsLargePacketsWithoutDroppingOrUsingTheMainThread() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        let complete = expectation(description: "real worker pool submits the complete upload")
        harness.adapter.queue.sync {
            harness.adapter.scheduleEncryption = nil
            var count = 0 // Accessed only by transport.send on the adapter owner queue.
            transport.onSend = { datagram in
                XCTAssertFalse(Thread.isMainThread)
                if datagram.first == 4, datagram.count > 32 {
                    count += 1
                    if count == 5_000 { complete.fulfill() }
                }
            }
        }
        var packet = Harness.packet + Data(repeating: 0xab, count: 1_200 - Harness.packet.count)
        packet[2] = 0x04
        packet[3] = 0xb0
        harness.packetIO.deliver(Array(repeating: packet, count: 5_000))
        wait(for: [complete], timeout: 15)
        harness.drain()
        XCTAssertEqual(transport.dataPackets.count, 5_000)
        XCTAssertEqual(harness.droppedPacketCount, 0)
        XCTAssertEqual(harness.queuedPacketBytes, 0)
        XCTAssertEqual(harness.packetIO.maximumPendingReads, 1)
        XCTAssertTrue(transport.mainThreadOperations.isEmpty)
        XCTAssertTrue(harness.packetIO.mainThreadOperations.isEmpty)
        harness.stop(self)
    }

    func testUpdateDropsOldEncryptionResultsAndContinuesWithNewPackets() throws {
        let harness = try Harness()
        harness.start(self)
        let old = try XCTUnwrap(harness.transports.transports.first)
        old.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 8))
        harness.drain()
        let updated = expectation(description: "update while encryption held")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 2)
        let current = try XCTUnwrap(harness.transports.transports.last)
        current.deliver(Harness.response)
        harness.drain()
        harness.packetIO.deliver([]) // Release the outstanding read owned by the old configuration.
        harness.drain()
        var newPacket = Harness.packet
        newPacket[4] = 0x7f
        harness.packetIO.deliver(Array(repeating: newPacket, count: 4))
        harness.drain()
        harness.holdEncryption = false
        harness.drain()
        XCTAssertTrue(old.dataPackets.isEmpty)
        XCTAssertEqual(try current.dataPackets.map(Harness.decrypt), Array(repeating: newPacket, count: 4))
        XCTAssertEqual(current.dataPackets.map(Harness.counter), Array(UInt64(1)...4))
    }

    func testExpiredSessionCannotSendWorkThatFinishedLate() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 8))
        harness.drain()
        XCTAssertGreaterThan(harness.scheduledEncryptionCount, 0)
        harness.advance(to: 1180)
        harness.holdEncryption = false
        harness.drain()
        XCTAssertTrue(transport.dataPackets.isEmpty, "An expired reservation must never reach UDP")
    }

    func testSuccessfulRekeyReencryptsHeldPacketsOnceUnderTheNewSession() throws {
        let harness = try Harness(freshRekeyKeys: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        harness.holdEncryption = true
        let packets = (UInt8(0)..<96).map { index -> Data in
            var packet = Harness.packet
            packet[4] = index
            return packet
        }
        harness.packetIO.deliver(packets)
        harness.drain()
        let oldJobs = harness.takeEncryptionJobs()
        XCTAssertGreaterThan(oldJobs.count, 0)
        harness.adapter.queue.sync { harness.clock.time = 1120 }
        harness.packetIO.deliver([Harness.packet]) // Fresh traffic requests the120-second rekey.
        harness.drain()
        harness.advance(to: 1120)
        transport.deliver(Harness.rekeyResponse)
        harness.drain()
        harness.completeEncryptionJobs(oldJobs)
        XCTAssertTrue(transport.dataPackets.isEmpty, "Completed old-session ciphertext must not be submitted")
        XCTAssertGreaterThan(harness.scheduledEncryptionCount, 0, "The raw packets are prepared again for the new session")
        harness.holdEncryption = false
        harness.drain()
        let newKey = Data(hex: "48c538b2e953f2b5704acbe14e416089077227e3216b24ea96ece3b13ffc13e6")
        XCTAssertEqual(try transport.dataPackets.map { try Harness.decrypt($0, key: newKey) }, packets + [Harness.packet])
        XCTAssertEqual(transport.dataPackets.map(Harness.counter), Array(UInt64(1)...97))
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2, "Replacing stale work must not start another handshake")
    }

    func testAuthenticatedServerInitiationClearsTheOldUnansweredDataDeadline() throws {
        let harness = try Harness(freshRekeyKeys: true, responderFixture: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.initiation)
        harness.drain()
        transport.deliver(Harness.sentTransport)
        harness.drain()
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        harness.advance(to: 1010)
        transport.deliver(Harness.rekeyInitiation)
        harness.drain()
        XCTAssertEqual(transport.sent.last, Harness.rekeyResponse)
        harness.advance(to: 1015)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 1,
                       "The authenticated server initiation answered prior data; its old 15-second timer cannot initiate another handshake")
    }

    func testAuthenticatedServerInitiationRetainsAnExistingCrossedHandshakeRetryEpisode() throws {
        let harness = try Harness(responderFixture: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.initiation)
        harness.drain()
        XCTAssertEqual(transport.sent.last, Harness.response)
        harness.advance(to: 1005)
        XCTAssertEqual(transport.sent.filter { $0.first == 1 }.count, 2,
                       "An unconfirmed crossed exchange still retries with a fresh initiation")
    }

    func testServerInitiationWaitsForConfirmationAndDeliversItsFirstIPPacket() async throws {
        let harness = try Harness(responderFixture: true)
        harness.packetIO.interfaceMTU = 1420 // Match the independent fixture's alignment padding.
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.initiation)
        harness.drain()
        XCTAssertEqual(transport.sent.last, Harness.response)
        let pendingHandshake = try await harness.adapter.getMostRecentHandshake()
        XCTAssertEqual(pendingHandshake, 0)
        harness.packetIO.deliver([Harness.packet])
        harness.drain()
        XCTAssertTrue(transport.dataPackets.isEmpty, "Unconfirmed responder keys cannot send queued IP packets")
        transport.deliver(Harness.sentTransport)
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenPackets, [Harness.packet], "Confirmation must not consume the first IP packet")
        XCTAssertEqual(transport.dataPackets, [Harness.receivedTransport], "The confirmed response keys send from nonce zero")
        let confirmedHandshake = try await harness.adapter.getMostRecentHandshake()
        XCTAssertEqual(confirmedHandshake, 1_700_000_000)
        XCTAssertTrue(transport.sent.filter { $0.first == 4 && $0.count == 32 }.isEmpty, "A responder does not echo confirmation keepalives")
    }

    func testServerInitiatedRekeyResponsePrecedesQueuedDataWhenAControlSlotOpens() throws {
        let harness = try Harness(freshRekeyKeys: true, responderFixture: true)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.initiation)
        harness.drain()
        transport.deliver(Harness.sentTransport)
        harness.drain()
        transport.automaticallyCompleteSends = false
        harness.packetIO.deliver(Array(repeating: Harness.packet, count: 128))
        harness.drain()
        XCTAssertEqual(transport.pendingSends.count, 63)
        harness.advance(to: 1025)
        XCTAssertEqual(transport.pendingSends.count, 64, "Persistent keepalive can use the reserved slot")
        transport.deliver(Harness.rekeyInitiation)
        harness.drain()
        let count = transport.sent.count
        transport.pendingSends.removeFirst()(nil)
        harness.drain()
        XCTAssertEqual(transport.sent.count, count + 1)
        XCTAssertEqual(transport.sent.last, Harness.rekeyResponse, "The bounded response gets priority over queued IP packets")
    }

    func testSingleReceivedPacketIsWrittenWithoutWaitingForAFullBatch() throws {
        let harness = try Harness()
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        transport.deliver(Harness.receivedTransport)
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenBatches, [[Harness.packet]])
        XCTAssertNotNil(transport.received, "The next receive is already armed")
    }

    func testReceiveBatchWritesOnlyAuthenticatedPacketsWithMatchingFamilies() throws {
        let supplied = try Harness.configuration()
        var configuredPeer = supplied.peers[0]
        configuredPeer.allowedIPs.append(try XCTUnwrap(IPAddressRange(from: "::/0")))
        let configuration = TunnelConfiguration(name: supplied.name, interface: supplied.interface, peers: [configuredPeer])
        let harness = try Harness(configuration: configuration)
        harness.start(self)
        let transport = try XCTUnwrap(harness.transports.transports.first)
        transport.deliver(Harness.response)
        harness.drain()
        var ipv6 = Data(repeating: 0, count: 40)
        ipv6[0] = 0x60
        ipv6[6] = 59
        ipv6[7] = 64
        var forged = try Harness.incoming(counter: 1, packet: Harness.packet)
        forged[forged.count - 1] ^= 1
        harness.packetIO.onWrite = {
            XCTAssertNotNil(transport.received, "Rearm UDP reads before decrypting and writing the current batch")
        }
        transport.deliverBatch([
            Data([0xff]), Harness.receivedTransport, Harness.receivedTransport,
            forged, try Harness.incoming(counter: 2, packet: ipv6)
        ])
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenBatches, [[Harness.packet, ipv6]])
        XCTAssertEqual(harness.packetIO.writtenFamilies, [[AF_INET, AF_INET6]])
        XCTAssertTrue(harness.packetIO.mainThreadOperations.isEmpty)
    }

    func testStaleReceivedBatchCannotWriteOrRearmAfterUpdate() throws {
        let harness = try Harness()
        harness.start(self)
        let oldTransport = try XCTUnwrap(harness.transports.transports.first)
        oldTransport.deliver(Harness.response)
        harness.drain()
        let oldReceive = try XCTUnwrap(oldTransport.received)
        let oldRequestCount = oldTransport.receiveRequests
        let updated = expectation(description: "updated")
        harness.adapter.update(tunnelConfiguration: harness.configuration, reassert: true) { error in
            XCTAssertNil(error)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 2)
        oldReceive([Harness.receivedTransport], nil)
        harness.drain()
        XCTAssertTrue(harness.packetIO.writtenBatches.isEmpty)
        XCTAssertEqual(oldTransport.receiveRequests, oldRequestCount)
        let current = try XCTUnwrap(harness.transports.transports.last)
        current.deliverBatch([Harness.response, Harness.receivedTransport])
        harness.drain()
        XCTAssertEqual(harness.packetIO.writtenBatches, [[Harness.packet]])
    }

    func testUDPReadAheadDeliversASinglePacketThenRefillsAcrossABurst() throws {
        let serverQueue = DispatchQueue(label: "native-wireguard-test-server")
        let clientQueue = DispatchQueue(label: "native-wireguard-test-client")
        let listening = expectation(description: "UDP listener ready")
        let firstPacket = expectation(description: "single packet delivered without filling batch")
        let burst = expectation(description: "more packets than the receive window delivered")
        let listener = try NWListener(using: .udp, on: .any)
        var connections: [NWConnection] = [] // Owned by serverQueue.
        listener.stateUpdateHandler = { state in
            if case .ready = state { listening.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connections.append(connection)
            connection.start(queue: serverQueue)
            connection.receiveMessage { data, _, _, error in
                XCTAssertNil(error)
                XCTAssertEqual(data, Data([0xff]))
                connection.send(content: Data([0xfe]), completion: .contentProcessed { XCTAssertNil($0) })
                connection.receiveMessage { data, _, _, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(data, Data([0xfd]))
                    connection.batch {
                        for index in UInt8(0)..<64 {
                            connection.send(content: Data([index]), completion: .contentProcessed { XCTAssertNil($0) })
                        }
                    }
                }
            }
        }
        listener.start(queue: serverQueue)
        defer {
            listener.cancel()
            serverQueue.async { connections.forEach { $0.cancel() } }
        }
        wait(for: [listening], timeout: 3)
        let port = try XCTUnwrap(listener.port)
        let transport = UDPWireGuardTransport(endpoint: Endpoint(host: "127.0.0.1", port: port))
        defer { transport.cancel() }
        clientQueue.async {
            var packets: [Data] = []
            var requestedBurst = false
            func receiveNext() {
                transport.receive { batch, error in
                    XCTAssertNil(error)
                    packets.append(contentsOf: batch)
                    if !requestedBurst, packets.contains(Data([0xfe])) {
                        requestedBurst = true
                        firstPacket.fulfill()
                        transport.send(Data([0xfd])) { XCTAssertNil($0) }
                    }
                    if packets.count >= 65 {
                        XCTAssertEqual(packets.count, 65)
                        XCTAssertEqual(Set(packets), Set((UInt8(0)..<64).map { Data([$0]) } + [Data([0xfe])]))
                        burst.fulfill()
                    } else {
                        receiveNext()
                    }
                }
            }
            transport.start(queue: clientQueue) { state in
                if case .ready = state {
                    receiveNext()
                    transport.send(Data([0xff])) { XCTAssertNil($0) }
                }
            }
        }
        wait(for: [firstPacket, burst], timeout: 5, enforceOrder: true)
    }

    private final class Clock { var time: TimeInterval = 1000 }

    private final class Harness {
        let clock = Clock()
        let packetIO = PacketIO()
        let transports = TransportFactory()
        let configuration: TunnelConfiguration
        let adapter: NativeWireGuardAdapter
        var holdEncryption = false
        private let encryptionJobs = EncryptionJobs()
        private let protocolTimers = ProtocolTimers()
        private let workerQueue = DispatchQueue(label: "native-wireguard-test-encryption", attributes: .concurrent)

        init(configuration supplied: TunnelConfiguration? = nil, freshRekeyKeys: Bool = false,
             maximumQueuedBytes: Int = 32 * 1024 * 1024, responderFixture: Bool = false,
             observePeer: ((WireGuardPeer) -> Void)? = nil,
             recordProtocolTimers: Bool = false, retryJitter: @escaping () -> TimeInterval = { 0 }) throws {
            let clock = self.clock
            let transports = self.transports
            configuration = try supplied ?? Self.configuration(responder: responderFixture)
            adapter = NativeWireGuardAdapter(
                io: packetIO.io,
                makeTransport: { transports.make($0) },
                makePeer: { configuration in
                    var index: UInt32 = responderFixture ? 0x05060707 : 0x01020304
                    var handshake = 0
                    let peer = try WireGuardPeer(
                        privateKey: configuration.interface.privateKey.rawValue,
                        peerPublicKey: configuration.peers[0].publicKey.rawValue,
                        ephemeralPrivateKey: {
                            let byte: UInt8 = responderFixture
                                ? (freshRekeyKeys && handshake > 2 ? 0x77 : 0x44)
                                : (freshRekeyKeys && handshake > 1 ? 0x66 : 0x33)
                            return Data(repeating: byte, count: 32)
                        },
                        senderIndex: { defer { index &+= 1 }; handshake += 1; return index },
                        now: { clock.time },
                        timestamp: { Data(hex: freshRekeyKeys && handshake > 1 ? "400000006000000000000002" : "400000006000000000000001") }
                    )
                    observePeer?(peer)
                    return peer
                },
                monotonicTime: { clock.time },
                epochTime: { 1_700_000_000 },
                maximumQueuedBytes: maximumQueuedBytes,
                retryJitter: retryJitter
            )
            let encryptionJobs = self.encryptionJobs
            adapter.scheduleEncryption = { encryptionJobs.jobs.append($0) }
            if recordProtocolTimers {
                let protocolTimers = self.protocolTimers
                adapter.scheduleProtocolTimer = { deadline, fire in protocolTimers.entries.append((deadline, fire)) }
            }
        }

        func start(_ test: XCTestCase) {
            let started = test.expectation(description: "start")
            adapter.start(tunnelConfiguration: configuration) { error in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertNil(error)
                started.fulfill()
            }
            test.wait(for: [started], timeout: 2)
            drain()
        }

        func stop(_ test: XCTestCase) {
            let stopped = test.expectation(description: "stop")
            adapter.stop { error in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertNil(error)
                stopped.fulfill()
            }
            test.wait(for: [stopped], timeout: 2)
            drain()
        }

        var scheduledEncryptionCount: Int { adapter.queue.sync { encryptionJobs.jobs.count } }
        var queuedPacketBytes: Int { adapter.queue.sync { adapter.queuedPacketBytes } }
        var droppedPacketCount: UInt64 { adapter.queue.sync { adapter.droppedPacketCount } }

        func takeEncryptionJobs() -> [() -> Void] {
            adapter.queue.sync {
                let jobs = encryptionJobs.jobs
                encryptionJobs.jobs.removeAll()
                return jobs
            }
        }

        func completeEncryptionJobs(_ jobs: [() -> Void]) {
            runEncryption(jobs)
            drain()
        }

        func completeFirstEncryptionJob() {
            let job = adapter.queue.sync { encryptionJobs.jobs.isEmpty ? nil : encryptionJobs.jobs.removeFirst() }
            guard let job else { XCTFail("No held encryption job"); return }
            completeEncryptionJobs([job])
        }

        func completeLastEncryptionJob() {
            let job = adapter.queue.sync { encryptionJobs.jobs.popLast() }
            guard let job else { XCTFail("No held encryption job"); return }
            runEncryption([job])
            drain()
        }

        func drain() {
            var previousProgress: [Int]?
            var stablePasses = 0
            for _ in 0..<1024 {
                adapter.queue.sync {}
                adapter.queue.sync {}
                let jobs = holdEncryption ? [] : takeEncryptionJobs()
                if jobs.isEmpty {
                    let progress = adapter.queue.sync {
                        [transports.transports.count, transports.transports.reduce(0) { $0 + $1.sent.count },
                         packetIO.readCount, packetIO.settings.count, encryptionJobs.jobs.count, adapter.queuedPacketBytes]
                    }
                    stablePasses = progress == previousProgress ? stablePasses + 1 : 0
                    previousProgress = progress
                    if stablePasses >= 2 { return }
                } else {
                    runEncryption(jobs)
                    stablePasses = 0
                    previousProgress = nil
                }
            }
            XCTFail("Adapter did not reach a stable encryption state")
        }

        private func runEncryption(_ jobs: [() -> Void]) {
            let group = DispatchGroup()
            for job in jobs {
                workerQueue.async(group: group) {
                    XCTAssertFalse(Thread.isMainThread)
                    job()
                }
            }
            XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        }
        var protocolDeadline: TimeInterval? { adapter.queue.sync { protocolTimers.entries.last?.deadline } }
        var protocolTimerCallback: (() -> Void)? { adapter.queue.sync { protocolTimers.entries.last?.fire } }

        func fireProtocolTimer(at time: TimeInterval) {
            adapter.queue.sync {
                guard let entry = protocolTimers.entries.last, let deadline = entry.deadline else {
                    XCTFail("No recorded protocol timer is armed")
                    return
                }
                guard time + 0.000_000_001 >= deadline else {
                    XCTFail("A protocol timer cannot fire before its recorded scheduled deadline")
                    return
                }
                clock.time = max(time, deadline)
                entry.fire()
            }
            drain()
        }

        func advance(to time: TimeInterval) {
            adapter.queue.sync { clock.time = time; adapter.tick() }
            drain()
        }

        static func response(to initiation: Data, configuration: TunnelConfiguration) throws -> Data {
            var response = Self.response
            response.replaceSubrange(8..<12, with: initiation[4..<8])
            let macKey = WireGuardCrypto.hash(Data("mac1----".utf8) + configuration.interface.privateKey.publicKey.rawValue)
            response.replaceSubrange(60..<76, with: WireGuardCrypto.mac(key: macKey, data: response.prefix(60)))
            return response
        }

        static func configurationWithoutPersistentKeepalive() throws -> TunnelConfiguration {
            let configuration = try Self.configuration()
            var peer = configuration.peers[0]
            peer.persistentKeepAlive = 0
            return TunnelConfiguration(name: configuration.name, interface: configuration.interface, peers: [peer])
        }

        static func configuration(responder: Bool = false, persistentKeepAlive: UInt16 = 25) throws -> TunnelConfiguration {
            let key = try XCTUnwrap(PrivateKey(rawValue: Data(repeating: responder ? 0x22 : 0x11, count: 32)))
            let peerHex = responder
                ? "7b4e909bbe7ffe44c465a220037d608ee35897d31ef972f07f74892cb0f73f13"
                : "0faa684ed28867b97f4a6a2dee5df8ce974e76b7018e3f22a1c4cf2678570f20"
            let publicKey = try XCTUnwrap(PublicKey(rawValue: Data(hex: peerHex)))
            let address = try XCTUnwrap(IPAddressRange(from: "10.0.0.1/32"))
            let route = try XCTUnwrap(IPAddressRange(from: "0.0.0.0/0"))
            let interface = InterfaceConfiguration(privateKey: key, addresses: [address], includedRoutes: [route], excludedRoutes: [])
            var peer = PeerConfiguration(publicKey: publicKey)
            peer.endpoint = Endpoint(host: "127.0.0.1", port: 51820)
            peer.allowedIPs = [route]
            peer.persistentKeepAlive = persistentKeepAlive
            return TunnelConfiguration(name: "test", interface: interface, peers: [peer])
        }

        // Generated independently by DuckWireGuardTests/Fixtures/generate.py (Python/OpenSSL).
        static let initiation = Data(hex: "01000000040302017b0d47d93427f8311160781c7c733fd89f88970aef490d8aa0ee19a4cb8a1b1481e498317da959fba46669572516a5e6c021bfa620bb6c56ca0082e1feae14988c2c64d024c617734a263f76a008df04d0f94bad8bb4afc2e1c269541d1b066b58e5a8cefa484f88e3369943e42d7b9b5b83543df8dc6547ff83cee900000000000000000000000000000000")
        static let rekeyInitiation = Data(hex: "0100000005030201219e4d800da968d2a5fcb009c784f4746c7138edb9ee4844b739e830b05cf42455796ee41b0c2b97e8da58f84b5cd964349bc2321b53cfb3999dd049b6b9ab8e1b6128747551308486036e3bd896e159f9e6fc9516bc7230af8f1e66c092089b18f58624416a865cac8a1d20697642c4b7c462f03ea6ee620168775d00000000000000000000000000000000")
        static let sentTransport = Data(hex: "0400000008070605000000000000000091ccbaaa294b87de65274175b0526f1449a948ec516e0072ded74eb0347d3731743a9caa8a943253bd730ed771470e8c")
        static let response = Data(hex: "020000000807060504030201ff2ee45601ec1b67310c7790404585ae697331eee1c1f8cf2419731c1fff3e6bed648bdfb34e27bba57cd1fe14ce04192b28cda1f9ac12c628924b8f86010d6c00000000000000000000000000000000")
        static let rekeyResponse = Data(hex: "0200000009070605050302011cf579aba45a10ba1d1ef06d91fca2aa9ed0a1150515653155405d0b18cb9a67b6521f39aefe1305c397aac692e08ff5c7a63f5b59fc18cc1a875e7b5d6b580700000000000000000000000000000000")
        static let packet = Data(hex: "4500001400000000400100000a0000010a000002")
        static let receivedTransport = Data(hex: "0400000004030201000000000000000076018b7cff7f19ec0e698e888983dc9070bed57817dda77713f2bd460ce7a2c25d94bc26cc03aede58192f61963fa262")

        static func packetWithLength(_ length: Int) -> Data {
            var packet = Self.packet + Data(repeating: 0xab, count: length - Self.packet.count)
            packet[2] = UInt8(length >> 8)
            packet[3] = UInt8(truncatingIfNeeded: length)
            return packet
        }

        static func counter(_ datagram: Data) -> UInt64 {
            (0..<8).reduce(UInt64(0)) { $0 | UInt64(datagram[8 + $1]) << ($1 * 8) }
        }

        static func decrypt(_ datagram: Data) throws -> Data {
            let key = Data(hex: "e07b709efbfd0361a08a9de658ceb3847d648c207ed71d4dbdfe248bef23a651")
            return try decrypt(datagram, key: key)
        }

        static func decrypt(_ datagram: Data, key: Data) throws -> Data {
            let plaintext = try WireGuardCrypto.open(key: key, counter: counter(datagram), ciphertext: datagram.dropFirst(16))
            let length = Int(plaintext[2]) << 8 | Int(plaintext[3])
            return Data(plaintext.prefix(length))
        }

        static func incoming(counter: UInt64, packet: Data) throws -> Data {
            let key = Data(hex: "f76ba55a113d83abf16240859ca361a9017ae9fbac0b4aa43179112c40e0163f")
            let header = Data([4, 0, 0, 0, 4, 3, 2, 1]) + withUnsafeBytes(of: counter.littleEndian) { Data($0) }
            let padded = packet + Data(repeating: 0, count: (16 - packet.count % 16) % 16)
            return header + (try WireGuardCrypto.seal(key: key, counter: counter, plaintext: padded))
        }
    }

    private final class ProtocolTimers {
        // Only the adapter owner queue accesses scheduled callbacks.
        var entries: [(deadline: TimeInterval?, fire: () -> Void)] = []
    }

    private final class EncryptionJobs {
        // Only the adapter's owner queue reads or mutates this array.
        var jobs: [() -> Void] = []
    }

    private final class PacketIO {
        var settings: [NEPacketTunnelNetworkSettings?] = []
        var delaySettings = false
        var settingsCompletion: ((Swift.Error?) -> Void)?
        var readCompletion: (([Data], [NSNumber]) -> Void)?
        var readCount = 0
        var pendingReads = 0
        var maximumPendingReads = 0
        var writtenPackets: [Data] = []
        var writtenBatches: [[Data]] = []
        var writtenFamilies: [[Int32]] = []
        var onWrite: (() -> Void)?
        var reasserting: [Bool] = []
        var cancelledErrors: [Swift.Error] = []
        var mainThreadOperations: [String] = []
        var interfaceMTU: Int?
        var interfaceMTUReadCount = 0

        var io: NativeWireGuardAdapter.IO {
            .init(
                applySettings: { settings, completion in
                    if Thread.isMainThread { self.mainThreadOperations.append("settings") }
                    self.settings.append(settings)
                    self.settingsCompletion = completion
                    if !self.delaySettings { completion(nil) }
                },
                readPackets: { completion in
                    if Thread.isMainThread { self.mainThreadOperations.append("read") }
                    self.readCount += 1
                    self.pendingReads += 1
                    self.maximumPendingReads = max(self.maximumPendingReads, self.pendingReads)
                    self.readCompletion = { packets, protocols in
                        self.pendingReads -= 1
                        completion(packets, protocols)
                    }
                },
                writePackets: { packets, families in
                    if Thread.isMainThread { self.mainThreadOperations.append("write") }
                    self.onWrite?()
                    self.writtenBatches.append(packets)
                    self.writtenFamilies.append(families.map(\.int32Value))
                    self.writtenPackets += packets
                    return true
                },
                setReasserting: { self.reasserting.append($0) },
                cancelTunnel: { self.cancelledErrors.append($0) },
                interfaceMTU: {
                    if Thread.isMainThread { self.mainThreadOperations.append("mtu") }
                    self.interfaceMTUReadCount += 1
                    return self.interfaceMTU
                }
            )
        }

        func deliver(_ packets: [Data]) {
            let completion = readCompletion
            readCompletion = nil
            completion?(packets, packets.map { _ in NSNumber(value: AF_INET) })
        }
    }

    private final class TransportFactory {
        var transports: [Transport] = []
        var autoReady = true
        func make(_ endpoint: Endpoint) -> NativeWireGuardTransport {
            let transport = Transport()
            transport.autoReady = autoReady
            transports.append(transport)
            return transport
        }
    }

    private final class Transport: NativeWireGuardTransport {
        var stateChanged: ((NWConnection.State) -> Void)?
        var received: (([Data], NWError?) -> Void)?
        var receiveRequests = 0
        var sent: [Data] = []
        var pendingSends: [(NWError?) -> Void] = []
        var automaticallyCompleteSends = true
        var autoReady = true
        var cancelled = false
        var mainThreadOperations: [String] = []
        var dataPackets: [Data] { sent.filter { $0.first == 4 && $0.count > 32 } }
        var onSend: ((Data) -> Void)?

        func start(queue: DispatchQueue, stateChanged: @escaping (NWConnection.State) -> Void) {
            if Thread.isMainThread { mainThreadOperations.append("start") }
            self.stateChanged = stateChanged
            if autoReady { stateChanged(.ready) }
        }
        func send(_ datagram: Data, completion: @escaping (NWError?) -> Void) {
            if Thread.isMainThread { mainThreadOperations.append("send") }
            sent.append(datagram)
            onSend?(datagram)
            if automaticallyCompleteSends { completion(nil) } else { pendingSends.append(completion) }
        }
        func receive(completion: @escaping ([Data], NWError?) -> Void) {
            if Thread.isMainThread { mainThreadOperations.append("receive") }
            receiveRequests += 1
            received = completion
        }
        func cancel() { cancelled = true }
        func deliver(_ packet: Data) { deliverBatch([packet]) }
        func deliverBatch(_ packets: [Data]) { let callback = received; received = nil; callback?(packets, nil) }
        func completeSends() { let callbacks = pendingSends; pendingSends = []; callbacks.forEach { $0(nil) } }
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16) ?? 0
        })
    }
}
#endif
