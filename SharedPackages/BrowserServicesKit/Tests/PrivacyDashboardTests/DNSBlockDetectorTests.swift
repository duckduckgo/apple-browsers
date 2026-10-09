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
            ("::ffff:10.0.0.1", .privateIP),
            ("::ffff:192.168.1.1", .privateIP),
            ("::ffff:224.0.0.1", .invalid),
            ("::ffff:192.0.2.1", .invalid),
            ("::ffff:1.1.1.1", .resolved),
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

    @available(iOS 16, macOS 13, *)
    @Test("Reserved, multicast, documentation and translation ranges resolve as invalid, and their neighbors don't",
          .timeLimit(.minutes(1)),
          arguments: [
            // 240.0.0.0/4
            ("240.0.0.0", DNSResolution.invalid),
            ("255.255.255.255", .invalid),
            // 224.0.0.0/4
            ("224.0.0.0", .invalid),
            ("239.255.255.255", .invalid),
            ("223.255.255.255", .resolved),
            // 192.0.0.0/24
            ("192.0.0.0", .invalid),
            ("192.0.0.170", .invalid),
            ("192.0.0.255", .invalid),
            ("191.255.255.255", .resolved),
            ("192.0.1.0", .resolved),
            // 192.0.2.0/24
            ("192.0.2.0", .invalid),
            ("192.0.2.255", .invalid),
            ("192.0.1.255", .resolved),
            ("192.0.3.0", .resolved),
            // 198.51.100.0/24
            ("198.51.100.0", .invalid),
            ("198.51.100.255", .invalid),
            ("198.51.99.255", .resolved),
            ("198.51.101.0", .resolved),
            // 203.0.113.0/24
            ("203.0.113.0", .invalid),
            ("203.0.113.255", .invalid),
            ("203.0.112.255", .resolved),
            ("203.0.114.0", .resolved),
            // 64:ff9b::/96
            ("64:ff9b::", .invalid),
            ("64:ff9b::ffff:ffff", .invalid),
            ("64:ff9a:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("64:ff9b::1:0:0", .resolved),
            // 64:ff9b:1::/48
            ("64:ff9b:1::", .invalid),
            ("64:ff9b:1:ffff:ffff:ffff:ffff:ffff", .invalid),
            ("64:ff9b:0:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("64:ff9b:2::", .resolved),
            // 2002::/16
            ("2002::", .invalid),
            ("2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .invalid),
            ("2001:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("2003::", .resolved),
            // ff00::/8
            ("ff00::", .invalid),
            ("ff02::1", .invalid),
            ("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .invalid),
            ("feff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            // 2001:db8::/32
            ("2001:db8::", .invalid),
            ("2001:db8:ffff:ffff:ffff:ffff:ffff:ffff", .invalid),
            ("2001:db7:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("2001:db9::", .resolved),
            // 3fff::/20
            ("3fff::", .invalid),
            ("3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff", .invalid),
            ("3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff", .resolved),
            ("3fff:1000::", .resolved),
            // 100:0:0:1::/64, next to the 100::/64 discard prefix
            ("100:0:0:1::", .invalid),
            ("100:0:0:1:ffff:ffff:ffff:ffff", .invalid),
            ("100::ffff:ffff:ffff:ffff", .blocked),
            ("100:0:0:2::", .resolved)
          ])
    func invalidResolution(host: String, expected: DNSResolution) async {
        #expect(await DNSBlockDetector().resolution(for: host) == expected)
    }
}
