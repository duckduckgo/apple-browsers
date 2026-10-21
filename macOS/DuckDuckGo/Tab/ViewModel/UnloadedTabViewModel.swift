//
//  UnloadedTabViewModel.swift
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

/// View model for an unloaded (not yet materialized) tab.
///
/// Conforms to `TabBarViewModel` so the tab bar can render unloaded tabs
/// identically to loaded ones. All publishers emit static values since
/// an unloaded tab has no live webView producing state changes.
final class UnloadedTabViewModel: TabBarViewModel, Previewable {

    let unloadedTab: UnloadedTab
    private let fileStore: FileStore

    init(unloadedTab: UnloadedTab,
         fileStore: FileStore = NSApplication.shared.delegateTyped.fileStore) {
        self.unloadedTab = unloadedTab
        self.fileStore = fileStore
        self.storedFavicon = unloadedTab.favicon
    }

    // MARK: - TabBarViewModel

    var uuid: TabIdentifier { unloadedTab.uuid }
    var tabContent: Tab.TabContent { unloadedTab.content }
    var isPinned: Bool { false }
    var title: String {
        unloadedTab.content.displayTitle(pageTitle: unloadedTab.title, pageURL: url)
    }
    var url: URL? { unloadedTab.content.urlForWebView }

    var titleAndLoadingStatusPublisher: AnyPublisher<(String, Bool), Never> {
        Just((title, false)).eraseToAnyPublisher()
    }

    var favicon: NSImage? { storedFavicon }

    @Published private var storedFavicon: NSImage?
    var faviconPublisher: Published<NSImage?>.Publisher { $storedFavicon }

    var tabContentPublisher: AnyPublisher<Tab.TabContent, Never> {
        Just(unloadedTab.content).eraseToAnyPublisher()
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

    var isSuspended: Bool {
        unloadedTab.isSuspended
    }
    var canBeSuspended: Bool { false }

    // MARK: - Previewable

    private var cachedSnapshot: NSImage?
    private var snapshotLoadAttempted = false

    var shouldShowPreview: Bool { true }

    var addressBarString: String {
        unloadedTab.content.userEditableUrl?.absoluteString ?? ""
    }

    var snapshot: NSImage? {
        if let cachedSnapshot { return cachedSnapshot }
        guard !snapshotLoadAttempted else { return nil }
        snapshotLoadAttempted = true

        guard let idString = unloadedTab.tabSnapshotIdentifier,
              let uuid = UUID(uuidString: idString) else { return nil }

        let url = URL.persistenceLocation(for: "\(TabSnapshotStore.directoryName)/\(uuid.uuidString)")
        guard let data = fileStore.loadData(at: url),
              let image = NSImage(data: data) else { return nil }

        cachedSnapshot = image
        return image
    }
}
