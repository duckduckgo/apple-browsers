//
//  UTIFooterWarningResolver.swift
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

import AIChat
import Foundation

struct UTIFooterWarningResolver {

    func resolve(limits: DuckAiUsageLimits) -> UTIFooterWarning? {
        let candidates = [
            warning(for: limits.weekly, window: .weekly),
            warning(for: limits.daily, window: .daily)
        ].compactMap { $0 }

        return candidates.max { Self.rank(of: $0) < Self.rank(of: $1) }
    }

    private func warning(for usage: DuckAiUsageLimitWindow?, window: UTIFooterUsageWindow) -> UTIFooterWarning? {
        guard let usage else { return nil }
        guard usage.percentUsed < 100 else {
            return .limitReached(window: window, resetsAt: usage.resetsAt)
        }
        guard let threshold = UTIFooterUsageThreshold.allCases.last(where: { Double($0.rawValue) <= usage.percentUsed }) else {
            return nil
        }
        return .usageThreshold(window: window, threshold: threshold, resetsAt: usage.resetsAt)
    }

    private static func rank(of warning: UTIFooterWarning) -> Int {
        switch warning {
        case .limitReached: 100
        case .usageThreshold(_, let threshold, _): threshold.rawValue
        }
    }
}
