//
//  VPNIPLeakCheckWideEventDataTests.swift
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
import PixelKit
@testable import VPN

final class VPNIPLeakCheckWideEventDataTests: XCTestCase {

    func testJSONParameters_allSuccess() {
        let data = makeEventData()
        data.trigger = .tunnelStart
        data.latencyMsBucketed = 2000
        data.ipv4Http = .success
        data.ipv4Https = .success
        data.ipv4Stun = .success
        data.ipv6Http = .success
        data.ipv6Https = .success
        data.ipv6Stun = .success

        let params = data.jsonParameters()

        XCTAssertEqual(params["feature.data.ext.trigger"] as? String, "tunnel_start")
        XCTAssertEqual(params["feature.data.ext.latency_ms_bucketed"] as? Int, 2000)
        XCTAssertEqual(params["feature.data.ext.ipv4.http.status"] as? String, "success")
        XCTAssertEqual(params["feature.data.ext.ipv4.https.status"] as? String, "success")
        XCTAssertEqual(params["feature.data.ext.ipv4.stun.status"] as? String, "success")
        XCTAssertEqual(params["feature.data.ext.ipv6.http.status"] as? String, "success")
        XCTAssertEqual(params["feature.data.ext.ipv6.https.status"] as? String, "success")
        XCTAssertEqual(params["feature.data.ext.ipv6.stun.status"] as? String, "success")
        XCTAssertNil(params["feature.data.ext.status_reason"])
        XCTAssertNil(params["feature.data.ext.ipv4.leak_ip_type"])
    }

    func testJSONParameters_leakWithError() {
        let data = makeEventData()
        data.trigger = .reassert
        data.latencyMsBucketed = 4000
        data.ipv4Http = .success
        data.ipv4Https = .leak
        data.ipv4Stun = .error(NSError(domain: "NWErrorDomain", code: -65554))
        data.ipv4LeakIPType = .public
        data.ipv6Http = .success
        data.ipv6Https = .success
        data.ipv6Stun = .success

        let params = data.jsonParameters()

        XCTAssertEqual(params["feature.data.ext.trigger"] as? String, "reassert")
        XCTAssertEqual(params["feature.data.ext.ipv4.https.status"] as? String, "leak")
        XCTAssertEqual(params["feature.data.ext.ipv4.stun.status"] as? String, "error")
        XCTAssertEqual(params["feature.data.ext.ipv4.stun.error_domain"] as? String, "NWErrorDomain")
        XCTAssertEqual(params["feature.data.ext.ipv4.stun.error_code"] as? Int, -65554)
        XCTAssertEqual(params["feature.data.ext.ipv4.leak_ip_type"] as? String, "public")
    }

    func testJSONParameters_leakWithOctetMatches_emitsPerTestKeys() {
        let data = makeEventData()
        data.ipv4Http = .leak(octet1Matched: true, octet2Matched: true, octet3Matched: false, octet4Matched: true)
        data.ipv4Https = .success
        data.ipv4Stun = .leak(octet1Matched: false, octet2Matched: false, octet3Matched: false, octet4Matched: false)

        let params = data.jsonParameters()

        XCTAssertEqual(params["feature.data.ext.ipv4.http.leak_octet1_matched"] as? Bool, true)
        XCTAssertEqual(params["feature.data.ext.ipv4.http.leak_octet2_matched"] as? Bool, true)
        XCTAssertEqual(params["feature.data.ext.ipv4.http.leak_octet3_matched"] as? Bool, false)
        XCTAssertEqual(params["feature.data.ext.ipv4.http.leak_octet4_matched"] as? Bool, true)

        XCTAssertNil(params["feature.data.ext.ipv4.https.leak_octet1_matched"])
        XCTAssertNil(params["feature.data.ext.ipv4.https.leak_octet2_matched"])
        XCTAssertNil(params["feature.data.ext.ipv4.https.leak_octet3_matched"])
        XCTAssertNil(params["feature.data.ext.ipv4.https.leak_octet4_matched"])

        XCTAssertEqual(params["feature.data.ext.ipv4.stun.leak_octet1_matched"] as? Bool, false)
        XCTAssertEqual(params["feature.data.ext.ipv4.stun.leak_octet4_matched"] as? Bool, false)
    }

    func testJSONParameters_ipv6Leak_doesNotEmitOctetKeys() {
        let data = makeEventData()
        data.ipv6Http = .leak
        data.ipv6Https = .leak
        data.ipv6Stun = .leak
        data.ipv6LeakIPType = .public

        let params = data.jsonParameters()

        XCTAssertEqual(params["feature.data.ext.ipv6.http.status"] as? String, "leak")
        XCTAssertNil(params["feature.data.ext.ipv6.http.leak_octet1_matched"])
        XCTAssertNil(params["feature.data.ext.ipv6.https.leak_octet1_matched"])
        XCTAssertNil(params["feature.data.ext.ipv6.stun.leak_octet1_matched"])
    }

    func testJSONParameters_statusReason() {
        let data = makeEventData()
        data.statusReason = "checks_errored"
        let params = data.jsonParameters()
        XCTAssertEqual(params["feature.data.ext.status_reason"] as? String, "checks_errored")
    }

    func testMetadata() {
        XCTAssertEqual(VPNIPLeakCheckWideEventData.metadata.featureName, "vpn-ip-leak-check")
        XCTAssertEqual(VPNIPLeakCheckWideEventData.metadata.version, "1.1.0")
        #if os(iOS)
        XCTAssertEqual(VPNIPLeakCheckWideEventData.metadata.type, "ios-vpn-ip-leak-check")
        #elseif os(macOS)
        XCTAssertEqual(VPNIPLeakCheckWideEventData.metadata.type, "macos-vpn-ip-leak-check")
        #endif
    }

    private func makeEventData() -> VPNIPLeakCheckWideEventData {
        VPNIPLeakCheckWideEventData(trigger: .tunnelStart)
    }
}
