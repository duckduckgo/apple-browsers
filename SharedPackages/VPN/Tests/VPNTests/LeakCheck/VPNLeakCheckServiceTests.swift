//
//  VPNLeakCheckServiceTests.swift
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
import PixelKit
@testable import VPN

final class VPNLeakCheckServiceTests: XCTestCase {

    /// `NWInterface` has no public initializer, so tests obtain a real one (typically loopback)
    /// from `NWPathMonitor`. The mock leak-test clients ignore the interface, so wrapping any real
    /// interface in `.resolved` is enough to keep the service from skipping the check.
    private static let systemInterface: NWInterface = {
        final class Box: @unchecked Sendable {
            var interface: NWInterface?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            guard box.interface == nil else { return }
            if let first = path.availableInterfaces.first {
                box.interface = first
                semaphore.signal()
            }
        }
        monitor.start(queue: .global())
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            monitor.cancel()
            preconditionFailure("Timed out obtaining a system NWInterface for tests")
        }
        monitor.cancel()
        guard let interface = box.interface else {
            preconditionFailure("No NWInterface available for tests")
        }
        return interface
    }()

    private func makeEgressInfo(ip: String = "1.2.3.4", name: String = "test-server") -> LeakCheckEgressInfo {
        LeakCheckEgressInfo(ipAddress: ip, name: name)
    }

    private func makeEgressInfoProvider(ip: String = "1.2.3.4", name: String = "test-server") -> VPNLeakCheckService.EgressInfoProvider {
        let info = LeakCheckEgressInfo(ipAddress: ip, name: name)
        return { info }
    }

    func testAllTestsMatchEgress_allSuccess() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .success)
        XCTAssertEqual(data.ipv4Https?.status, .success)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertEqual(data.ipv6Http?.status, .success)
        XCTAssertEqual(data.ipv6Https?.status, .success)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
        XCTAssertNil(data.ipv4LeakIPType)
    }

    func testIPv4Mismatch_detectsLeakAndClassifiesType() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .leak)
        XCTAssertEqual(data.ipv4Http?.octet1Matched, false)
        XCTAssertEqual(data.ipv4Http?.octet2Matched, false)
        XCTAssertEqual(data.ipv4Http?.octet3Matched, false)
        XCTAssertEqual(data.ipv4Http?.octet4Matched, false)
        XCTAssertEqual(data.ipv4Https?.status, .leak)
        XCTAssertEqual(data.ipv4Https?.octet1Matched, false)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertNil(data.ipv4Stun?.octet1Matched)
        XCTAssertNil(data.ipv4Stun?.octet2Matched)
        XCTAssertNil(data.ipv4Stun?.octet3Matched)
        XCTAssertNil(data.ipv4Stun?.octet4Matched)
        XCTAssertEqual(data.ipv4LeakIPType, .public)
    }

    /// The i3d VPN egress pool can NAT a single flow's traffic across multiple IPs in the same /24,
    /// so the externally observed IP can differ from the egress IP we expected. We treat a same-/24
    /// match as success rather than a leak.
    func testIPv4SameClassCSubnet_treatedAsSuccess() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "162.245.204.123", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "162.245.204.99", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(ip: "162.245.204.118"),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .success)
        XCTAssertEqual(data.ipv4Https?.status, .success)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertNil(data.ipv4LeakIPType)
    }

    func testIPv4DifferentClassCSubnet_detectsLeak() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "162.245.205.118", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "162.245.204.118", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(ip: "162.245.204.118"),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .leak)
        XCTAssertEqual(data.ipv4Http?.octet1Matched, true)
        XCTAssertEqual(data.ipv4Http?.octet2Matched, true)
        XCTAssertEqual(data.ipv4Http?.octet3Matched, false)
        XCTAssertEqual(data.ipv4Http?.octet4Matched, true)
        XCTAssertEqual(data.ipv4Https?.status, .leak)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertEqual(data.ipv4LeakIPType, .public)
    }

    func testIPv4Leak_perTestOctetPatternsAreIndependent() async throws {
        // HTTP returns a /24 mismatch (octet 3 differs), STUN returns a totally different IP.
        let http = MockLeakCheckHTTPClient(ipv4: "162.245.205.118", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "9.8.7.6", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(ip: "162.245.204.118"),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .leak)
        XCTAssertEqual(data.ipv4Http?.octet1Matched, true)
        XCTAssertEqual(data.ipv4Http?.octet2Matched, true)
        XCTAssertEqual(data.ipv4Http?.octet3Matched, false)
        XCTAssertEqual(data.ipv4Http?.octet4Matched, true)
        XCTAssertEqual(data.ipv4Stun?.status, .leak)
        XCTAssertEqual(data.ipv4Stun?.octet1Matched, false)
        XCTAssertEqual(data.ipv4Stun?.octet2Matched, false)
        XCTAssertEqual(data.ipv4Stun?.octet3Matched, false)
        XCTAssertEqual(data.ipv4Stun?.octet4Matched, false)
    }

    func testIPv4MalformedObservedIP_recordedAsErrorNotLeak() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "not-an-ip", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .error)
        XCTAssertEqual(data.ipv4Http?.errorDomain, "VPNLeakCheckIPError")
        XCTAssertEqual(data.ipv4Http?.errorCode, 1)
        XCTAssertEqual(data.ipv4Https?.status, .error)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertNil(data.ipv4LeakIPType)
        if case .unknown(let reason) = wideEvent.lastCompletedStatus {
            XCTAssertEqual(reason, "checks_errored")
        } else {
            XCTFail("expected UNKNOWN status")
        }
    }

    func testIPv4MalformedEgressIP_recordedAsErrorNotLeak() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(ip: "garbage"),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .error)
        XCTAssertEqual(data.ipv4Http?.errorDomain, "VPNLeakCheckIPError")
        XCTAssertEqual(data.ipv4Http?.errorCode, 2)
        XCTAssertEqual(data.ipv4Https?.status, .error)
        XCTAssertEqual(data.ipv4Stun?.status, .error)
        XCTAssertNil(data.ipv4LeakIPType)
    }

    func testIPv6Response_detectsLeak() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6: "2001:db8::1")
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv6Http?.status, .leak)
        XCTAssertEqual(data.ipv6Https?.status, .leak)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
        XCTAssertEqual(data.ipv6LeakIPType, .public)
    }

    func testIPv6PostConnectionError_recordedAsError() async throws {
        let http = MockLeakCheckHTTPClient(
            ipv4: "1.2.3.4",
            ipv6Error: LeakCheckHTTPResponseParser.ParseError.nonSuccessStatus(500)
        )
        let stun = MockLeakCheckSTUNClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.cannotFindHost)
        )
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv6Http?.status, .error)
        XCTAssertEqual(data.ipv6Https?.status, .error)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
    }

    func testIPv6TimeoutError_mapsToSuccess() async throws {
        let http = MockLeakCheckHTTPClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.timedOut)
        )
        let stun = MockLeakCheckSTUNClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.timedOut)
        )
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv6Http?.status, .success)
        XCTAssertEqual(data.ipv6Https?.status, .success)
    }

    func testIPv6ConnectionError_mapsToSuccess() async throws {
        let http = MockLeakCheckHTTPClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.cannotFindHost)
        )
        let stun = MockLeakCheckSTUNClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.cannotFindHost)
        )
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv6Http?.status, .success)
        XCTAssertEqual(data.ipv6Https?.status, .success)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
    }

    func testIPv4LeakTestError_recordedAsError() async throws {
        let http = MockLeakCheckHTTPClient(ipv4Error: URLError(.timedOut), ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .error)
        XCTAssertEqual(data.ipv4Http?.errorDomain, URLError.errorDomain)
        XCTAssertEqual(data.ipv4Http?.errorCode, URLError.timedOut.rawValue)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
    }

    func testStatus_failureBeatsError() async {
        let http = MockLeakCheckHTTPClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4Error: URLError(.timedOut), ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        if case .failure = wideEvent.lastCompletedStatus {
            // ok
        } else {
            XCTFail("expected FAILURE status, got \(String(describing: wideEvent.lastCompletedStatus))")
        }
        XCTAssertNil(wideEvent.lastCompletedData?.statusReason)
    }

    func testStatus_errorBeatsSuccess() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4Error: URLError(.timedOut), ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)

        if case .unknown(let reason) = wideEvent.lastCompletedStatus {
            XCTAssertEqual(reason, "checks_errored")
        } else {
            XCTFail("expected UNKNOWN status")
        }
        XCTAssertEqual(wideEvent.lastCompletedData?.statusReason, "checks_errored")
    }

    func testLatencyBucketing_isPopulatedAndCapped() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )
        await service.runCheck(trigger: .tunnelStart)
        let bucket = try XCTUnwrap(wideEvent.lastCompletedData?.latencyMsBucketed)
        XCTAssertGreaterThanOrEqual(bucket, 500)
        XCTAssertLessThanOrEqual(bucket, 5_000)
        XCTAssertEqual(bucket % 500, 0)
    }

    func testInFlightTrigger_isDropped() async {
        let http = SlowMockHTTPClient(delaySeconds: 1)
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        async let first: Void = service.runCheck(trigger: .tunnelStart)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.runCheck(trigger: .periodic)
        _ = await first

        XCTAssertEqual(wideEvent.startedFlows.count, 1)
    }

    func testPeriodicTimer_firesAfterInterval() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 0.2,
            cooldown: 0,
            debounceDelay: 0
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.start()
        try await Task.sleep(nanoseconds: 700_000_000)
        await service.stop()

        XCTAssertGreaterThanOrEqual(wideEvent.startedFlows.count, 2)
        for case let data as VPNIPLeakCheckWideEventData in wideEvent.startedFlows where data.trigger == .periodic {
            return
        }
        XCTFail("no periodic-triggered flow observed")
    }

    func testCooldown_rejectsFollowUp() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 60,
            debounceDelay: 0
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)
        await service.runCheck(trigger: .periodic)

        XCTAssertEqual(wideEvent.startedFlows.count, 1)
    }

    func testCooldown_reassertBypassesCooldown() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 60,
            debounceDelay: 0
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)
        await service.runCheck(trigger: .reassert)

        XCTAssertEqual(wideEvent.startedFlows.count, 2)
    }

    func testCooldown_rekeyBypassesCooldown() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 60,
            debounceDelay: 0
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .tunnelStart)
        await service.runCheck(trigger: .rekey)

        XCTAssertEqual(wideEvent.startedFlows.count, 2)
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .rekey)
    }

    func testEgressIPChange_duringInflightCheck_usesSnapshot() async {
        let http = SlowMockHTTPClient(delaySeconds: 0.3, returnIP: "1.2.3.4")
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let box = MutableEgressInfoBox(makeEgressInfo())
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: { box.value },
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        async let checkTask: Void = service.runCheck(trigger: .tunnelStart)
        try? await Task.sleep(nanoseconds: 100_000_000)
        box.value = makeEgressInfo(ip: "5.6.7.8")
        _ = await checkTask

        XCTAssertEqual(wideEvent.lastCompletedData?.ipv4Http?.status, .success)
        XCTAssertEqual(wideEvent.lastCompletedData?.ipv4Https?.status, .success)
    }

    func testEgressIPChange_beforeCheck_changesComparison() async {
        let http = MockLeakCheckHTTPClient(ipv4: "5.6.7.8", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "5.6.7.8", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let box = MutableEgressInfoBox(makeEgressInfo())
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: { box.value },
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )
        box.value = makeEgressInfo(ip: "5.6.7.8")
        await service.runCheck(trigger: .reassert)

        XCTAssertEqual(wideEvent.lastCompletedData?.ipv4Http?.status, .success)
    }

    func testStop_discardsInflightFlow() async {
        let http = SlowMockHTTPClient(delaySeconds: 5)
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManagerWithPending()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        Task { await service.runCheck(trigger: .tunnelStart) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertGreaterThan(wideEvent.discardedCount, 0)
        await service.stop()
    }

    func testRunCheckAfterStop_isNoOp() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.stop()
        await service.runCheck(trigger: .tunnelStart)

        XCTAssertEqual(wideEvent.startedFlows.count, 0)
        XCTAssertNil(wideEvent.lastCompletedData)
    }

    func testScheduleCheck_tunnelStart_honorsDebounceDelay() async throws {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.3
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .tunnelStart)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(wideEvent.startedFlows.count, 0, "check should not have run yet during the delay")

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(wideEvent.startedFlows.count, 1)
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .tunnelStart)
    }

    func testScheduleCheck_reassert_honorsDebounceDelay() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.3
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .reassert)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(wideEvent.startedFlows.count, 0, "reassert should wait for the debounce delay")

        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(wideEvent.startedFlows.count, 1)
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .reassert)
    }

    func testScheduleCheck_periodic_runsImmediately() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.3
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .periodic)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(wideEvent.startedFlows.count, 1)
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .periodic)
    }

    func testScheduleCheck_periodicDoesNotCancelPendingPathChangeCheck() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.3
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .rekey)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.scheduleCheck(trigger: .periodic)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(wideEvent.startedFlows.count, 0, "periodic should not interrupt a pending path-change debounce")

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(wideEvent.startedFlows.count, 1)
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .rekey)
    }

    func testRunCheck_periodicSkipsWhilePathChangeCheckIsPending() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let rekeyCompleted = expectation(description: "rekey leak check completes after debounce")
        wideEvent.onCompleteFlow = { rekeyCompleted.fulfill() }

        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.3
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .rekey)
        await service.runCheck(trigger: .periodic)
        XCTAssertEqual(wideEvent.startedFlows.count, 0, "periodic should be skipped while a path-change check is pending")

        await fulfillment(of: [rekeyCompleted], timeout: 5.0)
        XCTAssertEqual(wideEvent.startedFlows.count, 1)
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .rekey)
    }

    func testScheduleCheck_pathChangeCancelsInflightCheck() async {
        let http = SlowMockHTTPClient(delaySeconds: 5)
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManagerWithPending()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.3
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        Task { await service.runCheck(trigger: .periodic) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.scheduleCheck(trigger: .rekey)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertGreaterThan(wideEvent.discardedCount, 0)
    }

    func testScheduleCheck_stopBeforeDelayElapses_cancelsPendingCheck() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.5
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .tunnelStart)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.stop()
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(wideEvent.startedFlows.count, 0, "stop() should have cancelled the pending check before it fired")
        XCTAssertNil(wideEvent.lastCompletedData)
    }

    func testScheduleCheck_secondScheduleSupersedesFirst() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let config = LeakCheckConfiguration(
            host: "leakcheck.netp.duckduckgo.com",
            httpPort: 80, httpsPort: 443, stunPort: 3478,
            httpTimeout: 10, stunTimeout: 5,
            periodicInterval: 60 * 60,
            cooldown: 0,
            debounceDelay: 0.4
        )
        let service = VPNLeakCheckService(
            configuration: config,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.scheduleCheck(trigger: .tunnelStart)
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.scheduleCheck(trigger: .reassert)
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(wideEvent.startedFlows.count, 1, "the first scheduled check should have been cancelled by the second")
        XCTAssertEqual(wideEvent.lastCompletedData?.trigger, .reassert)
    }

    func testScheduleCheck_afterStop_isNoOp() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.stop()
        await service.scheduleCheck(trigger: .reassert)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(wideEvent.startedFlows.count, 0)
    }

    func testPathGenerationChange_duringInflightCheck_completesAsInterrupted() async {
        let http = SlowMockHTTPClient(delaySeconds: 0.3, returnIP: "5.6.7.8")
        let stun = MockLeakCheckSTUNClient(ipv4: "5.6.7.8", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let generation = MutablePathGenerationBox(0)
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .resolved(Self.systemInterface) },
            tunnelPathGeneration: { generation.value },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        async let checkTask: Void = service.runCheck(trigger: .periodic)
        try? await Task.sleep(nanoseconds: 100_000_000)
        generation.value = 1
        _ = await checkTask

        if case .unknown(let reason) = wideEvent.lastCompletedStatus {
            XCTAssertEqual(reason, "check_interrupted")
        } else {
            XCTFail("expected UNKNOWN status")
        }
        XCTAssertEqual(wideEvent.lastCompletedData?.statusReason, "check_interrupted")
        XCTAssertNil(wideEvent.lastCompletedData?.ipv4Http)
        XCTAssertNil(wideEvent.lastCompletedData?.ipv4LeakIPType)
    }

    // MARK: - Tunnel interface resolution

    /// When resolution yields a non-tunnel interface (`.unexpectedInterface`), the check must not
    /// run leak probes — it would compare against a non-tunnel egress and manufacture a false leak.
    /// Instead it fires a single UNKNOWN flow tagged with the unexpected-interface reason.
    func testUnexpectedTunnelInterface_recordsUnknownAndDoesNotProbe() async {
        let http = MockLeakCheckHTTPClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .unexpectedInterface },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        XCTAssertEqual(wideEvent.startedFlows.count, 1)
        if case .unknown(let reason) = wideEvent.lastCompletedStatus {
            XCTAssertEqual(reason, "unexpected_tunnel_interface")
        } else {
            XCTFail("expected UNKNOWN status, got \(String(describing: wideEvent.lastCompletedStatus))")
        }
        XCTAssertEqual(wideEvent.lastCompletedData?.statusReason, "unexpected_tunnel_interface")
        XCTAssertNil(wideEvent.lastCompletedData?.ipv4Http)
        XCTAssertNil(wideEvent.lastCompletedData?.ipv4LeakIPType)
    }

    /// When no interface can be resolved (`.unavailable`), the check is skipped silently — no flow
    /// is started, so it never surfaces as a leak, an error, or an UNKNOWN.
    func testUnavailableTunnelInterface_skipsWithoutFiringEvent() async {
        let http = MockLeakCheckHTTPClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressInfo: makeEgressInfoProvider(),
            tunnelInterface: { .unavailable },
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent
        )

        await service.runCheck(trigger: .periodic)

        XCTAssertEqual(wideEvent.startedFlows.count, 0)
        XCTAssertNil(wideEvent.lastCompletedData)
    }

    func testCompletePendingFlows_completesWithInterruptedReason() {
        let wideEvent = MockWideEventManagerWithPending()
        let pending = VPNIPLeakCheckWideEventData(trigger: .periodic)
        wideEvent.pending = [pending]

        VPNLeakCheckService.completeAllPendingFlows(wideEvent: wideEvent)

        XCTAssertEqual(wideEvent.completedWithReason.count, 1)
        XCTAssertEqual(wideEvent.completedWithReason.first, "check_interrupted")
    }

    // MARK: - shouldScheduleCheckAfterRekey

    func testShouldScheduleCheckAfterRekey_returnsFalseWhenPostRekeyIsNil() {
        let pre = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        XCTAssertFalse(VPNLeakCheckService.shouldScheduleCheckAfterRekey(preRekey: pre, postRekey: nil))
    }

    func testShouldScheduleCheckAfterRekey_returnsFalseWhenPreAndPostAreEqual() {
        let info = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        XCTAssertFalse(VPNLeakCheckService.shouldScheduleCheckAfterRekey(preRekey: info, postRekey: info))
    }

    func testShouldScheduleCheckAfterRekey_returnsTrueWhenEgressChanged() {
        let pre = LeakCheckEgressInfo(ipAddress: "1.2.3.4", name: "us-east")
        let post = LeakCheckEgressInfo(ipAddress: "5.6.7.8", name: "eu-west")
        XCTAssertTrue(VPNLeakCheckService.shouldScheduleCheckAfterRekey(preRekey: pre, postRekey: post))
    }
}

final class MockWideEventManagerWithPending: WideEventManaging, @unchecked Sendable {
    var pending: [VPNIPLeakCheckWideEventData] = []
    var completedWithReason: [String] = []
    var discardedCount = 0

    func startFlow<T: WideEventData>(_ data: T) {
        if let leak = data as? VPNIPLeakCheckWideEventData {
            pending.append(leak)
        }
    }
    func updateFlow<T: WideEventData>(_ data: T) {}
    func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void) {}
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        if case .unknown(let reason) = status {
            completedWithReason.append(reason)
        }
        if let leak = data as? VPNIPLeakCheckWideEventData {
            pending.removeAll { $0 === leak }
        }
        onComplete(true, nil)
    }
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool {
        if case .unknown(let reason) = status {
            completedWithReason.append(reason)
        }
        return true
    }
    func discardFlow<T: WideEventData>(_ data: T) {
        discardedCount += 1
        if let leak = data as? VPNIPLeakCheckWideEventData {
            pending.removeAll { $0 === leak }
        }
    }
    func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T? { nil }
    func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T] {
        return pending as? [T] ?? []
    }
}

final class MutableEgressInfoBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: LeakCheckEgressInfo?

    init(_ initial: LeakCheckEgressInfo?) {
        self._value = initial
    }

    var value: LeakCheckEgressInfo? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

final class MutablePathGenerationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64

    init(_ initial: UInt64) {
        self._value = initial
    }

    var value: UInt64 {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

final class SlowMockHTTPClient: LeakCheckHTTPClient, @unchecked Sendable {
    let delaySeconds: TimeInterval
    let returnIP: String
    init(delaySeconds: TimeInterval, returnIP: String = "1.2.3.4") {
        self.delaySeconds = delaySeconds
        self.returnIP = returnIP
    }
    func fetchIP(host: String, port: UInt16, usesTLS: Bool, ipVersion: IPVersion, timeout: TimeInterval, requiredInterface: NWInterface?) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        if ipVersion == .v6 { throw URLError(.cannotFindHost) }
        return returnIP
    }
}

// MARK: - Mocks

final class MockLeakCheckHTTPClient: LeakCheckHTTPClient, @unchecked Sendable {
    var ipv4: String?
    var ipv6: String?
    var ipv4Error: Error?
    var ipv6Error: Error?

    init(ipv4: String? = nil, ipv6: String? = nil, ipv4Error: Error? = nil, ipv6Error: Error? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.ipv4Error = ipv4Error
        self.ipv6Error = ipv6Error
    }

    func fetchIP(
        host: String,
        port: UInt16,
        usesTLS: Bool,
        ipVersion: IPVersion,
        timeout: TimeInterval,
        requiredInterface: NWInterface?
    ) async throws -> String {
        switch ipVersion {
        case .v4:
            if let error = ipv4Error { throw error }
            return ipv4 ?? ""
        case .v6:
            if let error = ipv6Error { throw error }
            return ipv6 ?? ""
        }
    }
}

final class MockLeakCheckSTUNClient: LeakCheckSTUNClient, @unchecked Sendable {
    var ipv4: String?
    var ipv6: String?
    var ipv4Error: Error?
    var ipv6Error: Error?

    init(ipv4: String? = nil, ipv6: String? = nil, ipv4Error: Error? = nil, ipv6Error: Error? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.ipv4Error = ipv4Error
        self.ipv6Error = ipv6Error
    }

    func fetchIP(
        host: String,
        port: UInt16,
        ipVersion: IPVersion,
        timeout: TimeInterval,
        requiredInterface: NWInterface?
    ) async throws -> String {
        switch ipVersion {
        case .v4:
            if let error = ipv4Error { throw error }
            return ipv4 ?? ""
        case .v6:
            if let error = ipv6Error { throw error }
            return ipv6 ?? ""
        }
    }
}

final class MockWideEventManager: WideEventManaging, @unchecked Sendable {
    var startedFlows: [Any] = []
    var lastCompletedData: VPNIPLeakCheckWideEventData?
    var lastCompletedStatus: WideEventStatus?
    var discardedCount = 0
    var onCompleteFlow: (() -> Void)?

    func startFlow<T: WideEventData>(_ data: T) {
        startedFlows.append(data)
    }
    func updateFlow<T: WideEventData>(_ data: T) {}
    func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void) {}
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        if let data = data as? VPNIPLeakCheckWideEventData {
            lastCompletedData = data
            lastCompletedStatus = status
        }
        onCompleteFlow?()
        onComplete(true, nil)
    }
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool {
        if let data = data as? VPNIPLeakCheckWideEventData {
            lastCompletedData = data
            lastCompletedStatus = status
        }
        return true
    }
    func discardFlow<T: WideEventData>(_ data: T) {
        discardedCount += 1
    }
    func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T? { nil }
    func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T] { [] }
}
