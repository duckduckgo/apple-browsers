//
//  DNSBlockDetectorTests.swift
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

import PrivacyDashboard
import Testing

struct DNSBlockDetectorTests {

    @available(iOS 16, macOS 13, *)
    @Test("Resolution reflects the addresses the host resolves to",
          .timeLimit(.minutes(1)),
          arguments: [
            ("0.0.0.0", DNSResolution.blocked),
            ("127.0.0.1", .blocked),
            ("::", .blocked),
            ("::1", .blocked),
            ("0.1.2.3", .blocked),
            ("127.0.0.2", .blocked),
            ("::ffff:0.0.0.0", .blocked),
            ("::ffff:127.0.0.1", .blocked),
            ("100::1", .blocked),
            ("10.0.0.1", .privateIP),
            ("fd00::1", .privateIP),
            ("1.1.1.1", .resolved),
            ("", .unresolved)
          ])
    func resolution(host: String, expected: DNSResolution) async {
        #expect(await DNSBlockDetector().resolution(for: host) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Private and link-local ranges resolve as privateIP, and their neighbors don't",
          .timeLimit(.minutes(1)),
          arguments: [
            // 10.0.0.0/8
            ("10.0.0.0", DNSResolution.privateIP),
            ("10.255.255.255", .privateIP),
            ("9.255.255.255", .resolved),
            ("11.0.0.0", .resolved),
            // 172.16.0.0/12
            ("172.16.0.0", .privateIP),
            ("172.31.255.255", .privateIP),
            ("172.15.255.255", .resolved),
            ("172.32.0.0", .resolved),
            // 192.168.0.0/16
            ("192.168.0.0", .privateIP),
            ("192.168.255.255", .privateIP),
            ("192.167.255.255", .resolved),
            ("192.169.0.0", .resolved),
            // 169.254.0.0/16
            ("169.254.0.0", .privateIP),
            ("169.254.255.255", .privateIP),
            ("169.253.255.255", .resolved),
            ("169.255.0.0", .resolved),
            // fc00::/7
            ("fc00::", .privateIP),
            ("fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .privateIP),
            ("fbff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("fe00::", .resolved),
            // fe80::/10
            ("fe80::", .privateIP),
            ("febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .privateIP),
            ("fe7f:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("fec0::", .resolved)
          ])
    func privateResolution(host: String, expected: DNSResolution) async {
        #expect(await DNSBlockDetector().resolution(for: host) == expected)
    }
}
