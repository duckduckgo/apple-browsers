//
//  VPNRoutingRange.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation

public enum VPNRoutingRange {

    public static let alwaysExcludedIPv4Range: [NetworkProtection.IPAddressRange] = [
        "127.0.0.0/8",    /* 255.0.0.0   Loopback */
        "169.254.0.0/16", /* 255.255.0.0 Link-local */
        "224.0.0.0/4",    /* 240.0.0.0   Multicast */
        "240.0.0.0/4",    /* 240.0.0.0   Class E */
    ]

    public static let alwaysExcludedIPv6Range: [NetworkProtection.IPAddressRange] = [
        "fe80::/10",  /* link local */
        "ff00::/8",   /* multicast */
        "fc00::/7",   /* local unicast */
        "::1/128",    /* loopback */
    ]

    public static let localNetworkRangeWithoutDNS: [NetworkProtection.IPAddressRange] = [
        "172.16.0.0/12",  /* 255.240.0.0 */
        "192.168.0.0/16", /* 255.255.0.0 */
    ]

    public static let localNetworkRange: [NetworkProtection.IPAddressRange] = [
        "10.0.0.0/8",     /* 255.0.0.0   */
        "172.16.0.0/12",  /* 255.240.0.0 */
        "192.168.0.0/16", /* 255.255.0.0 */
    ]

    public static let publicNetworkRange: [NetworkProtection.IPAddressRange] = [
        "1.0.0.0/8",
        "2.0.0.0/8",
        "3.0.0.0/8",
        "4.0.0.0/6",
        "8.0.0.0/7",
        "11.0.0.0/8",
        "12.0.0.0/6",
        "16.0.0.0/4",
        "32.0.0.0/3",
        "64.0.0.0/2",
        "128.0.0.0/3",
        "160.0.0.0/5",
        "168.0.0.0/6",
        "172.0.0.0/12",
        "172.32.0.0/11",
        "172.64.0.0/10",
        "172.128.0.0/9",
        "173.0.0.0/8",
        "174.0.0.0/7",
        "176.0.0.0/4",
        "192.0.0.0/9",
        "192.128.0.0/11",
        "192.160.0.0/13",
        "192.169.0.0/16",
        "192.170.0.0/15",
        "192.172.0.0/14",
        "192.176.0.0/12",
        "192.192.0.0/10",
        "193.0.0.0/8",
        "194.0.0.0/7",
        "196.0.0.0/6",
        "200.0.0.0/5",
        "208.0.0.0/4",
    ]
}
