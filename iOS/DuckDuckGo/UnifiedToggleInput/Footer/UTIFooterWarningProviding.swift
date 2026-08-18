//
//  UTIFooterWarningProviding.swift
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
import os.log

protocol UTIFooterWarningProviding {
    func currentWarning() -> UTIFooterWarning?
}

struct UTIFooterWarningProvider: UTIFooterWarningProviding {

    private let limitsStore: DuckAiUsageLimitsStore
    private let resolver: UTIFooterWarningResolver

    init(limitsStore: DuckAiUsageLimitsStore, resolver: UTIFooterWarningResolver = UTIFooterWarningResolver()) {
        self.limitsStore = limitsStore
        self.resolver = resolver
    }

    func currentWarning() -> UTIFooterWarning? {
        guard let limits = limitsStore.currentLimits() else { return nil }
        let warning = resolver.resolve(limits: limits)
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] resolved warning: \(String(describing: warning), privacy: .public)")
        return warning
    }
}
