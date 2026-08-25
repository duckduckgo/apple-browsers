//
//  SuggestionTrayDependencies.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Bookmarks
import BrowserServicesKit
import Core
import Persistence
import PrivacyConfig

/// Dependencies required for the suggestion tray
struct SuggestionTrayDependencies {
    let favoritesViewModel: FavoritesListInteracting
    let bookmarksDatabase: CoreDataDatabase
    let historyManager: HistoryManaging
    let tabsModelProvider: () -> TabsModelManaging
    let featureFlagger: FeatureFlagger
    let appSettings: AppSettings
    let aiChatSettings: AIChatSettingsProvider
    let featureDiscovery: FeatureDiscovery
    let newTabPageDependencies: SuggestionTrayViewController.NewTabPageDependencies
    let productSurfaceTelemetry: ProductSurfaceTelemetry
}
