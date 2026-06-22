//
//  DuckAIVoiceSessionTracker.swift
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

import Combine
import Foundation
import WebKit
import os.log

/// Reports which `Tab`s currently host a live Duck.ai voice session, so the tab
/// switcher can render the dark "live voice" card for them (a finished voice chat is
/// a persisted transcript instead — see `DuckAIGridItem`).
@MainActor
protocol DuckAIVoiceSessionTracking: AnyObject {

    func isVoiceSessionActive(for tab: Tab) -> Bool

    /// Emits whenever a voice session starts or ends, so observers (e.g. the open tab
    /// switcher) can refresh the affected cells.
    var changes: AnyPublisher<Void, Never> { get }
}

/// Tracks live Duck.ai voice sessions per `Tab`.
///
/// Source of truth is the `aiChatVoiceSessionStarted` / `aiChatVoiceSessionEnded`
/// user-script notifications Duck.ai posts when a `getUserMedia` voice session actually
/// begins/ends; each notification's `object` is the source `WKWebView`. Unlike macOS,
/// the iOS `Tab` model has no `webView`, so the webView is resolved back to its owning
/// `Tab` via the injected `tabForWebView` closure (production: `TabManager`). `Tab`s are
/// held weakly, so a closed tab evicts itself without an explicit "tab removed" hook.
///
/// The posting site (`AIChatUserScriptHandling`) is `@MainActor`, so the notifications
/// arrive on the main thread and the `@objc` handlers run synchronously there.
@MainActor
final class DuckAIVoiceSessionTracker: NSObject, DuckAIVoiceSessionTracking {

    private let activeTabs: NSHashTable<Tab> = .weakObjects()
    private let notificationCenter: NotificationCenter
    private let tabForWebView: (WKWebView) -> Tab?
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    /// - Parameters:
    ///   - notificationCenter: Source of the voice-session notifications. Injectable for tests.
    ///   - tabForWebView: Resolves a source `WKWebView` to its owning `Tab`. Production wires this
    ///     to `tabManager.controller(forWebView:)?.tabModel`.
    init(notificationCenter: NotificationCenter = .default,
         tabForWebView: @escaping (WKWebView) -> Tab?) {
        self.notificationCenter = notificationCenter
        self.tabForWebView = tabForWebView
        super.init()
        notificationCenter.addObserver(self, selector: #selector(voiceSessionStarted(_:)),
                                       name: .aiChatVoiceSessionStarted, object: nil)
        notificationCenter.addObserver(self, selector: #selector(voiceSessionEnded(_:)),
                                       name: .aiChatVoiceSessionEnded, object: nil)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func isVoiceSessionActive(for tab: Tab) -> Bool {
        activeTabs.contains(tab)
    }

    @objc private func voiceSessionStarted(_ note: Notification) {
        guard let tab = resolveTab(from: note, event: "started") else { return }
        activeTabs.add(tab)
        Logger.aiChat.debug("DuckAIVoiceSessionTracker: voice session STARTED for tab \(tab.uid, privacy: .public) (active=\(self.activeTabs.count, privacy: .public))")
        changesSubject.send()
    }

    @objc private func voiceSessionEnded(_ note: Notification) {
        guard let tab = resolveTab(from: note, event: "ended") else { return }
        activeTabs.remove(tab)
        Logger.aiChat.debug("DuckAIVoiceSessionTracker: voice session ENDED for tab \(tab.uid, privacy: .public) (active=\(self.activeTabs.count, privacy: .public))")
        changesSubject.send()
    }

    private func resolveTab(from note: Notification, event: String) -> Tab? {
        guard let webView = note.object as? WKWebView else {
            Logger.aiChat.debug("DuckAIVoiceSessionTracker: voiceSession\(event, privacy: .public) notification carried no WKWebView object")
            return nil
        }
        guard let tab = tabForWebView(webView) else {
            Logger.aiChat.debug("DuckAIVoiceSessionTracker: voiceSession\(event, privacy: .public) webView did not resolve to a Tab")
            return nil
        }
        return tab
    }
}
