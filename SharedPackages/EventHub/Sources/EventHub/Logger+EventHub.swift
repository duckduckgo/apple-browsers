//
//  Logger+EventHub.swift
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
import os.log

public extension Logger {
    /// Replaces the Windows implementation's `Diagnostic.cs` ETW source: every fail-safe boundary in
    /// EventHub logs here rather than swallowing silently. Local only — never PII, never a URL.
    ///
    /// `public` so each platform's wiring layer logs to the same subsystem, keeping all EventHub
    /// activity filterable as one stream.
    ///
    /// Only config-governed identifiers (pixel names, parameter names, bucket names, data keys) and
    /// error descriptions are interpolated as `.public`. Web-page-derived values — event types, event
    /// payloads and tab identifiers — are interpolated as `.private` and only at `debug` level, so they
    /// are redacted unless someone deliberately enables private-data logging on a development device.
    static let eventHub = Logger(subsystem: "EventHub", category: "")
}
