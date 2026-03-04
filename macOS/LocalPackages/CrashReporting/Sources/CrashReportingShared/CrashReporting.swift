//
//  CrashReporting.swift
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

import Common
import Crashes
import FeatureFlags
import Foundation
import Persistence
import PrivacyConfig

public protocol CrashReporting {
    func start() async
}

public protocol CrashReportPresenting {
    var content: String? { get }
}

public protocol SparkleCrashReportingFactory {
    static func instantiate(internalUserDecider: InternalUserDecider,
                            keyValueStore: any ThrowingKeyValueStoring,
                            crashSenderPixelEvents: EventMapping<CrashReportSenderError>?,
                            fireCrashPixel: @escaping (_ bundleID: String?, _ appVersion: String?, _ failedToReadCrashVersion: Bool) -> Void,
                            fireFailedToReadContentsPixel: @escaping () -> Void,
                            promptForConsent: @escaping (CrashReportPresenting) async -> Bool) -> any CrashReporting
}

@available(macOS 12.0, *)
public protocol AppStoreCrashReportingFactory {
    static func instantiate(internalUserDecider: InternalUserDecider,
                            featureFlagger: FeatureFlagger,
                            crashSenderPixelEvents: EventMapping<CrashReportSenderError>?,
                            fireCrashPixel: @escaping (_ parameters: [CrashReportPixelParameter: String]) -> Void,
                            promptForConsent: @escaping (_ crashPayload: Data) async -> Bool) -> any CrashReporting
}

/// Marker type extended by crash reporting packages with concrete `instantiate(...)` implementations.
public struct CrashReportingFactory {}
