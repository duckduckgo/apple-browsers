//
//  NetworkSignalsProviderTests.swift
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
import PrivacyDashboard
import Testing

struct NetworkSignalsProviderTests {

    @available(iOS 16, macOS 13, *)
    @Test("Disabled provider returns no signals and skips the ping", .timeLimit(.minutes(1)))
    func disabledProviderReturnsNil() async {
        let provider = makeProvider(isEnabled: false)

        #expect(provider.prefetchSignals() == nil)
        #expect(await provider.currentSignals() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ping is skipped when the network is unavailable", .timeLimit(.minutes(1)))
    func pingIsSkippedWithoutNetwork() async {
        let provider = makeProvider(networkType: .unavailable)

        #expect(provider.prefetchSignals() == nil)
        #expect(await provider.currentSignals()?.pingQuality == .unknown)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Signals combine path state, VPN issues and the prefetched ping", .timeLimit(.minutes(1)))
    func signalsCombineAllSources() async {
        let provider = makeProvider(networkType: .cellular, isConstrained: true, hasVPNIssues: true, pingQuality: .poor)

        await provider.prefetchSignals()?.value

        let expected = NetworkSignals(networkType: .cellular, isLowDataModeEnabled: true, hasVPNConnectivityIssues: true, pingQuality: .poor)
        #expect(await provider.currentSignals() == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ping quality is unknown until a prefetch completes", .timeLimit(.minutes(1)))
    func pingQualityIsUnknownWithoutPrefetch() async {
        let provider = makeProvider(pingQuality: .excellent)

        #expect(await provider.currentSignals()?.pingQuality == .unknown)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unrecognized ping qualities map to unknown", .timeLimit(.minutes(1)))
    func unrecognizedPingQualityMapsToUnknown() async {
        let provider = makeProvider(pingQuality: .unrecognized)

        await provider.prefetchSignals()?.value

        #expect(await provider.currentSignals()?.pingQuality == .unknown)
    }
}

private extension NetworkSignalsProviderTests {

    func makeProvider(isEnabled: Bool = true,
                      networkType: NetworkSignals.NetworkType = .wifi,
                      isConstrained: Bool = false,
                      hasVPNIssues: Bool = false,
                      pingQuality: PingQualityProviderMock.Quality = .good) -> NetworkSignalsProvider {
        NetworkSignalsProvider(pathProvider: NetworkPathProviderMock(currentPathState: NetworkPathState(networkType: networkType, isConstrained: isConstrained)),
                               vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviderMock(hasIssues: hasVPNIssues),
                               pingQualityProvider: PingQualityProviderMock(quality: pingQuality),
                               isEnabledProvider: { isEnabled })
    }
}

private final class NetworkPathProviderMock: NetworkPathProviding {
    let currentPathState: NetworkPathState

    init(currentPathState: NetworkPathState) {
        self.currentPathState = currentPathState
    }
}

private struct VPNConnectivityIssuesProviderMock: VPNConnectivityIssuesProviding {
    let hasIssues: Bool

    func isExperiencingVPNConnectivityIssues() async -> Bool {
        hasIssues
    }
}

private struct PingQualityProviderMock: PingQualityProviding {
    enum Quality: String {
        case excellent, good, poor, unrecognized
    }

    let quality: Quality

    func currentPingQuality() async -> Quality {
        quality
    }
}
