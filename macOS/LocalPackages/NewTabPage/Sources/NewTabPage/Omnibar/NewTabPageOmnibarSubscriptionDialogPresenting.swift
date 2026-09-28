//
//  NewTabPageOmnibarSubscriptionDialogPresenting.swift
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

/// Presents native subscription dialogs on behalf of the NTP omnibar. Which flow to run is
/// determined by which method is called; `source` only carries which picker triggered it, for telemetry.
@MainActor
public protocol NewTabPageOmnibarSubscriptionDialogPresenting {
    /// `async` because it re-resolves the current subscription tier before deciding whether to
    /// offer a free trial, rather than trusting the web's (potentially stale) choice of message.
    func showSubscriptionUpsellDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) async
    func showSubscriptionUpgradeDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource)
}
