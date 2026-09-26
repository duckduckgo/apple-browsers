//
//  CPMDiagnosticsFeatureFlags.swift
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

import Combine
import Foundation

public enum CPMBackgroundGraveyardCohort: String, Sendable, Equatable {
    case control
    case treatment
}

public enum CPMBackgroundGraveyardOutcome: String, Sendable, Equatable {
    case healthy
    case initializationFailed = "initialization_failed"
    case notMeasured = "not_measured"
}

/// Runtime switches for the CPM diagnostics layer. Implemented by the app on top of its `FeatureFlagger`; the
/// recorder re-reads the values on every `updatesPublisher` emission.
@MainActor
public protocol CPMDiagnosticsFeatureFlagsProviding: AnyObject {
    /// Whether `CPMBackgroundWebViewDelegateProxy` may be installed on the background web view. Turning it off at
    /// runtime hands WebKit's original navigation delegate back.
    var isBackgroundDelegateProxyEnabled: Bool { get }
    /// Assigns a stable cohort on the first eligible process termination. Returns nil when the experiment is inactive.
    func enrollInBackgroundGraveyardExperiment() -> CPMBackgroundGraveyardCohort?
    /// Emits whenever a value above may have changed (remote config update, local override).
    var updatesPublisher: AnyPublisher<Void, Never> { get }
}

/// Fixed values, for tests and for platforms that have not wired flags yet.
@MainActor
public final class CPMDiagnosticsStaticFeatureFlags: CPMDiagnosticsFeatureFlagsProviding {
    public var isBackgroundDelegateProxyEnabled: Bool {
        didSet { subject.send() }
    }
    public var backgroundGraveyardCohort: CPMBackgroundGraveyardCohort? {
        didSet { subject.send() }
    }
    private let subject = PassthroughSubject<Void, Never>()
    public var updatesPublisher: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    public init(isBackgroundDelegateProxyEnabled: Bool = true,
                backgroundGraveyardCohort: CPMBackgroundGraveyardCohort? = nil) {
        self.isBackgroundDelegateProxyEnabled = isBackgroundDelegateProxyEnabled
        self.backgroundGraveyardCohort = backgroundGraveyardCohort
    }

    public func enrollInBackgroundGraveyardExperiment() -> CPMBackgroundGraveyardCohort? {
        backgroundGraveyardCohort
    }
}
