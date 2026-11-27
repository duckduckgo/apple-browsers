//
//  DBPVPNConnectionStatusProviderTests.swift
//  DuckDuckGo
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

import Foundation
import Testing
import DataBrokerProtectionCore
import VPN
import VPNTestUtils
@testable import DuckDuckGo

@Suite("DBP VPN connection status provider")
struct DBPVPNConnectionStatusProviderTests {

    private var statusesAndExpectedStrings: [(status: ConnectionStatus, expected: String)] {
        [
            (.connected(connectedDate: Date(timeIntervalSince1970: 1_000)), "connected"),
            (.connecting, "connecting"),
            (.disconnected, "disconnected"),
            (.disconnecting, "disconnecting"),
            (.reasserting, "reasserting"),
            (.notConfigured, "not configured"),
            (.snoozing, "snoozing"),
        ]
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports the observer's current VPN status", .timeLimit(.minutes(1)))
    func reportsConnectionStatus() {
        for (status, expected) in statusesAndExpectedStrings {
            let observer = MockConnectionStatusObserver()
            observer.subject.send(status)
            let provider = DBPVPNConnectionStatusProvider(connectionObserver: observer)

            #expect(provider.connectionStatus == expected, "status: \(status)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Follows status changes after creation", .timeLimit(.minutes(1)))
    func followsStatusChanges() {
        let observer = MockConnectionStatusObserver()
        let provider = DBPVPNConnectionStatusProvider(connectionObserver: observer)
        provider.setUp()
        #expect(provider.connectionStatus == "disconnected")

        observer.subject.send(.connected(connectedDate: Date()))

        #expect(provider.connectionStatus == "connected")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reports bypass as unsupported whatever the VPN status", .timeLimit(.minutes(1)))
    func bypassIsUnsupported() {
        for (status, _) in statusesAndExpectedStrings {
            let observer = MockConnectionStatusObserver()
            observer.subject.send(status)
            let provider = DBPVPNConnectionStatusProvider(connectionObserver: observer)

            #expect(provider.bypassStatus == .unsupported, "status: \(status)")
            #expect(provider.bypassStatus.rawValue == "unsupported", "status: \(status)")
            #expect(!provider.isEnabled, "status: \(status)")
            #expect(!provider.isSupported, "status: \(status)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ignores attempts to turn bypass on", .timeLimit(.minutes(1)))
    func applyingBypassHasNoEffect() {
        let provider = DBPVPNConnectionStatusProvider(connectionObserver: MockConnectionStatusObserver())

        provider.applyVPNBypass(true)
        provider.isOnboardingShown = true

        #expect(!provider.isEnabled)
        #expect(provider.bypassStatus == .unsupported)
        #expect(!provider.isOnboardingShown)
    }
}
