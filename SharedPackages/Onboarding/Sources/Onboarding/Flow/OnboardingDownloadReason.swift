//
//  OnboardingDownloadReason.swift
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

/// Represents the user's self-reported reason for downloading the app.
///
/// The download reason is captured when the user answers the Motivation Screen shown
/// early in the default onboarding flow, and is used together with ``OnboardingFlowType``
/// to tailor which steps and content follow.
///
/// It is optional at every call site: it is `nil` for Duck.ai Custom Product Page flows
/// (which rely on ``OnboardingFlowType`` alone to drive content decisions) and for default-flow
/// steps that render before the user has made their choice.
///
/// - Note: The raw values are persisted (alongside ``OnboardingFlowType``) so the onboarding
///   flow can resume after an app relaunch.
public enum OnboardingDownloadReason: String, Equatable, CaseIterable {
    /// The user downloaded the app to browse the web more privately.
    case browserPrivately

    /// The user downloaded the app for private AI chat.
    case privateAIChat

    /// The user downloaded the app specifically wanting an experience without AI features.
    case noAI

    /// The user downloaded the app to block ads and trackers.
    case blockAds
}
