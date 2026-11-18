//
//  StandalonePIRDebugServer.swift
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

#if DEBUG
import DataBrokerProtectionCore
import DataBrokerProtectionDebugServer
import Foundation

/// A launch-owned host with no scheduler, XPC service, or access to the saved PIR profile.
public final class StandalonePIRDebugServer: DataBrokerProtectionDebugReadProviding {
    private var server: DataBrokerProtectionDebugHTTPServer?
    private let settings: DataBrokerProtectionSettings

    @MainActor
    public init(featureFlagger: DBPFeatureFlagging, configuration: DebugModeLaunchConfiguration) throws {
        settings = DataBrokerProtectionSettings(defaults: .dbp, debugEnvironment: configuration.environment)
        let runner = try DebugModeRunner(authenticationManager: UnauthenticatedDebugAccount(), featureFlagger: StandaloneFeatureFlagger(fallback: featureFlagger),
                                         isolated: true)
        let server = DataBrokerProtectionDebugHTTPServer(provider: self, logReader: DataBrokerProtectionOSLogReader(),
                                                         runManager: DebugModeRunManager(runner: runner), port: configuration.port, instanceID: configuration.instanceID,
                                                         prerequisiteReader: {
            DebugPrerequisiteResult(status: .unauthenticated, backend: "subscription", environment: "unavailable", authenticated: false)
        })
        self.server = server
        try server.start()
    }

    public var agentVersion: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown" }
    public var schedulerStateString: String { "standalone-debug" }
    public var lastSchedulerTrigger: Date? { nil }
    public var environmentName: String { settings.selectedEnvironment.rawValue }
    public var endpointURL: URL { settings.endpointURL }
    public var mainConfigETag: String? { nil }
    public var lastBrokerJSONUpdateCheck: Date { .distantPast }
    public func brokerProfileQueryData() throws -> [BrokerProfileQueryData] { [] }
}
private struct UnauthenticatedDebugAccount: DataBrokerProtectionAuthenticationManaging {
    var isUserAuthenticated: Bool { get async { false } }
    var isUserEligibleForFreeTrial: Bool { false }
    func accessToken() async -> String? { nil }
    func hasValidEntitlement() async throws -> Bool { false }
    func getAuthHeader() async -> String? { nil }
}

private struct StandaloneFeatureFlagger: DBPFeatureFlagging {
    let fallback: DBPFeatureFlagging
    var isForegroundRunningOnAppActiveFeatureOn: Bool { false }
    var isContinuedProcessingFeatureOn: Bool { false }
    var isCustomWebViewUserAgentOn: Bool { true }
    var isExtractedProfileRefreshOn: Bool { true }
    var isOptOutRetryErrorFrequencyExperimentOn: Bool { fallback.isOptOutRetryErrorFrequencyExperimentOn }
    var isChallengeSolverOn: Bool { fallback.isChallengeSolverOn }
}
#endif
