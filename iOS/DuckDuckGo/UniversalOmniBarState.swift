//
//  UniversalOmniBarState.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Core
import BrowserServicesKit

enum UniversalOmniBarState {
    struct EditingSuspendedState: OmniBarState {
        let baseState: OmniBarState

        var hasLargeWidth: Bool { baseState.hasLargeWidth }
        var showBackButton: Bool { baseState.showBackButton }
        var showForwardButton: Bool { baseState.showForwardButton }
        var showBookmarksButton: Bool { baseState.showBookmarksButton }
        var showAIChatButton: Bool { baseState.showAIChatButton }
        var clearTextOnStart: Bool { baseState.clearTextOnStart }
        var allowsTrackersAnimation: Bool { baseState.allowsTrackersAnimation }
        var showSearchLoupe: Bool { baseState.showSearchLoupe }
        var showPrivacyIcon: Bool { baseState.showPrivacyIcon }
        var showBackground: Bool { baseState.showBackground }
        var showClear: Bool { baseState.showClear }
        var showDismiss: Bool { baseState.showDismiss }
        var showAbort: Bool { baseState.showAbort }
        var showRefresh: Bool { baseState.showRefresh }
        var showShare: Bool { baseState.showShare }
        var showMenu: Bool { baseState.showMenu }
        var showSettings: Bool { baseState.showSettings }
        var showVoiceSearch: Bool { baseState.showVoiceSearch }
        var isBrowsing: Bool { baseState.isBrowsing }

        // MARK: deprecated
        let showCancel = false

        // MARK: meta
        var name: String { Type.name(self) }

        // MARK: state transitions
        var onEditingStoppedState: any OmniBarState { baseState.onEditingStoppedState }
        var onEditingStartedState: any OmniBarState { baseState.onEditingStartedState }
        var onTextClearedState: any OmniBarState { baseState.onTextClearedState }
        var onTextEnteredState: any OmniBarState { baseState.onTextEnteredState }
        var onBrowsingStartedState: any OmniBarState { baseState.onBrowsingStartedState }
        var onBrowsingStoppedState: any OmniBarState { baseState.onBrowsingStoppedState }
        var onEnterPhoneState: any OmniBarState { baseState.onEnterPhoneState }
        var onEnterPadState: any OmniBarState { baseState.onEnterPadState }
        var onReloadState: any OmniBarState { baseState.onReloadState }

        // MARK: init params
        let dependencies: OmnibarDependencyProvider
        let isLoading: Bool

        func withLoading() -> UniversalOmniBarState.EditingSuspendedState {
            Self.init(baseState: baseState, dependencies: dependencies, isLoading: true)
        }

        func withoutLoading() -> UniversalOmniBarState.EditingSuspendedState {
            Self.init(baseState: baseState, dependencies: dependencies, isLoading: false)
        }
    }

    /// OmniBarState used when a displaying AI Chat in 'full mode' (i.e in a tab)
    struct AIChatModeState: OmniBarState {
        let baseState: OmniBarState

        var hasLargeWidth: Bool { baseState.hasLargeWidth }
        let showBackButton = false
        let showForwardButton = false
        let showBookmarksButton = false
        let showAIChatButton = false
        let clearTextOnStart = false
        let allowsTrackersAnimation = false
        let showSearchLoupe = false
        let showPrivacyIcon = false
        let showBackground = false
        let showClear = false
        let showAbort = false
        let showRefresh = false
        let showShare = false
        let showMenu = false
        let showSettings = false
        let showCancel = false
        let showDismiss = false
        let showVoiceSearch = false
        let isBrowsing = false
        let showAIChatFullModeBranding = true

        var name: String { Type.name(self) }

        var onEditingStartedState: any OmniBarState {
            baseState.hasLargeWidth
                ? LargeOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: isLoading)
                : SmallOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: isLoading)
        }
        var onEditingStoppedState: any OmniBarState { self }
        var onTextClearedState: any OmniBarState {
            baseState.hasLargeWidth
                ? LargeOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: isLoading)
                : SmallOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: isLoading)
        }
        var onTextEnteredState: any OmniBarState {
            baseState.hasLargeWidth
                ? LargeOmniBarState.HomeTextEditingState(dependencies: dependencies, isLoading: isLoading)
                : SmallOmniBarState.HomeTextEditingState(dependencies: dependencies, isLoading: isLoading)
        }
        var onBrowsingStartedState: any OmniBarState {
            baseState.hasLargeWidth
                ? LargeOmniBarState.BrowsingNonEditingState(dependencies: dependencies, isLoading: isLoading)
                : SmallOmniBarState.BrowsingNonEditingState(dependencies: dependencies, isLoading: isLoading)
        }
        var onBrowsingStoppedState: any OmniBarState { self }
        var onEnterPadState: any OmniBarState {
            let largeBase = LargeOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
            return baseState.hasLargeWidth ? self : UniversalOmniBarState.AIChatModeState(baseState: largeBase, dependencies: dependencies, isLoading: isLoading)
        }
        var onEnterPhoneState: any OmniBarState {
            let smallBase = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
            return baseState.hasLargeWidth ? UniversalOmniBarState.AIChatModeState(baseState: smallBase, dependencies: dependencies, isLoading: isLoading) : self
        }
        var onReloadState: any OmniBarState { self }

        let dependencies: OmnibarDependencyProvider
        let isLoading: Bool

        func withLoading() -> UniversalOmniBarState.AIChatModeState {
            Self.init(baseState: baseState, dependencies: dependencies, isLoading: true)
        }

        func withoutLoading() -> UniversalOmniBarState.AIChatModeState {
            Self.init(baseState: baseState, dependencies: dependencies, isLoading: false)
        }
    }
}
