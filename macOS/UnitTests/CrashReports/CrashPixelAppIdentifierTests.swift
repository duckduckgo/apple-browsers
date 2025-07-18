//
//  CrashPixelAppIdentifierTests.swift
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

import Testing
@testable import DuckDuckGo_Privacy_Browser

struct CrashPixelAppIdentifierTests {

    enum BundleID {
        static let dmg = "com.duckduckgo.macos.browser"
        static let appStore = "com.duckduckgo.mobile.ios"
    }

    @Test("Initializer returns nil for app bundles")
    func testThatInitializerReturnsNilForAppBundles() {
        #expect(CrashPixelAppIdentifier(nil, mainBundleID: BundleID.dmg) == nil)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.macos.browser", mainBundleID: BundleID.dmg) == nil)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.mobile.ios", mainBundleID: BundleID.appStore) == nil)
    }

    @Test("Initializer returns .dbp for DBP agent bundles")
    func testThatInitializerReturnsDBPForDBPAgentBundles() {
        #expect(CrashPixelAppIdentifier("com.duckduckgo.macos.browser.DBP.backgroundAgent", mainBundleID: BundleID.dmg) == .dbp)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.mobile.ios.DBP.backgroundAgent", mainBundleID: BundleID.appStore) == .dbp)
    }

    @Test("Initializer returns .vnpAgent for VNP agent bundles")
    func testThatInitializerReturnsVPNAgentForVNPAgentBundles() {
        #expect(CrashPixelAppIdentifier("com.duckduckgo.macos.vpn", mainBundleID: BundleID.dmg) == .vpnAgent)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.mobile.ios.vpn.agent", mainBundleID: BundleID.appStore) == .vpnAgent)
    }

    @Test("Initializer returns .vpnExtension for VPN extension bundles")
    func testThatInitializerReturnsVPNExtensionForVPNExtensionBundles() {
        #expect(CrashPixelAppIdentifier("com.duckduckgo.macos.vpn.network-extension", mainBundleID: BundleID.dmg) == .vpnExtension)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.mobile.ios.vpn.agent.network-protection-extension", mainBundleID: BundleID.appStore) == .vpnExtension)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.mobile.ios.vpn.agent.network-extension", mainBundleID: BundleID.appStore) == .vpnExtension)
        #expect(CrashPixelAppIdentifier("com.duckduckgo.mobile.ios.vpn.agent.proxy", mainBundleID: BundleID.appStore) == .vpnExtension)
    }
}
