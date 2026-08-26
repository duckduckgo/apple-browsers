//
//  DuckAiUsageWarningPixelFiring.swift
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

/// What happened to a usage-limit message. The notice and cta ids are web's own, so native numbers
/// line up with the web banner's for the same message.
///
/// No percentage: the notice id and window already say which message this was, and the exact
/// percentage is both needlessly precise and not what any question here is about.
public enum DuckAiUsageWarningEvent: Equatable {
    case noticeShown(noticeID: DuckAiUsageNotice.ID, window: DuckAiUsageWindow)
    case ctaTapped(ctaID: DuckAiUsageCta.ID, noticeID: DuckAiUsageNotice.ID)
    case noticeDismissed(noticeID: DuckAiUsageNotice.ID)
}

/// Implemented per platform, because the surface a message appeared on (address bar, Prompt Bar,
/// omnibar, contextual sheet) belongs to the app rather than to this module.
public protocol DuckAiUsageWarningPixelFiring {
    func fire(_ event: DuckAiUsageWarningEvent)
}

public struct NullDuckAiUsageWarningPixelFiring: DuckAiUsageWarningPixelFiring {
    public init() {}
    public func fire(_ event: DuckAiUsageWarningEvent) {}
}
