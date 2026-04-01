//
//  SuspendedTabViewModel.swift
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

import AppKit
import Combine
import Foundation
import WebKit

/// View model for a suspended (not yet materialized) tab.
///
/// Conforms to `TabBarViewModel` so the tab bar can render suspended tabs
/// identically to loaded ones. All publishers emit static values since
/// a suspended tab has no live webView producing state changes.
final class SuspendedTabViewModel: TabBarViewModel {

    let suspendedTab: SuspendedTab

    init(suspendedTab: SuspendedTab) {
        self.suspendedTab = suspendedTab
        self.storedFavicon = suspendedTab.favicon
    }

    // MARK: - TabBarViewModel

    var tabContent: Tab.TabContent { suspendedTab.content }
    var isPinned: Bool { false }
    var title: String { suspendedTab.title ?? "" }
    var url: URL? { suspendedTab.content.urlForWebView }

    var titleAndLoadingStatusPublisher: AnyPublisher<(String, Bool), Never> {
        Just((title, false)).eraseToAnyPublisher()
    }

    var favicon: NSImage? { storedFavicon }

    @Published private var storedFavicon: NSImage?
    var faviconPublisher: Published<NSImage?>.Publisher { $storedFavicon }

    var tabContentPublisher: AnyPublisher<Tab.TabContent, Never> {
        Just(suspendedTab.content).eraseToAnyPublisher()
    }

    @Published private var storedUsedPermissions: Permissions = [:]
    var usedPermissionsPublisher: Published<Permissions>.Publisher { $storedUsedPermissions }

    var audioState: WKWebView.AudioState { .unmuted(isPlayingAudio: false) }

    var audioStatePublisher: AnyPublisher<WKWebView.AudioState, Never> {
        Just(.unmuted(isPlayingAudio: false)).eraseToAnyPublisher()
    }

    var canKillWebContentProcess: Bool { false }

    var crashIndicatorModel: TabCrashIndicatorModel { _crashIndicatorModel }
    private let _crashIndicatorModel = TabCrashIndicatorModel()

    var isLoadingPublisher: AnyPublisher<(Bool, WKError?), Never> {
        Just((false, nil)).eraseToAnyPublisher()
    }

    var renderingProgressDidChangePublisher: PassthroughSubject<Void, Never> {
        _renderingProgressDidChangePublisher
    }
    private let _renderingProgressDidChangePublisher = PassthroughSubject<Void, Never>()

    var isSuspended: Bool { true }
    var isSuspendedPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }
    var canBeSuspended: Bool { false }

    // MARK: - TabDataClearing

    /// Suspended tabs have no webView — signal completion immediately to prevent
    /// `TabCleanupPreparer` from hanging while waiting for a navigation callback.
    @MainActor
    func prepareForDataClearing(caller: TabCleanupPreparer) {
        caller.reportNoWebViewToClear()
    }
}
