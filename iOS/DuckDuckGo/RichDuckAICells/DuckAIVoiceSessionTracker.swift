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
    private let deactivationDelay: TimeInterval
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    /// - Parameters:
    ///   - notificationCenter: Source of the voice-session notifications. Injectable for tests.
    ///   - tabForWebView: Resolves a source `WKWebView` to its owning `Tab`. Production wires this
    ///     to `tabManager.controller(forWebView:)?.tabModel`.
    ///   - deactivationDelay: how long a tab stays "active" after its session ends, so the live card
    ///     holds until the transcript persists. Pass 0 in tests for synchronous deactivation.
    init(notificationCenter: NotificationCenter = .default,
         tabForWebView: @escaping (WKWebView) -> Tab?,
         deactivationDelay: TimeInterval = 0.5) {
        self.notificationCenter = notificationCenter
        self.tabForWebView = tabForWebView
        self.deactivationDelay = deactivationDelay
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
        dispatchPrecondition(condition: .onQueue(.main))
        guard let tab = resolveTab(from: note) else { return }
        activeTabs.add(tab)
        changesSubject.send()
    }

    @objc private func voiceSessionEnded(_ note: Notification) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let tab = resolveTab(from: note) else { return }
        // Hold the tab active briefly so the live card holds until the transcript persists (avoids a screenshot flash).
        // TODO: replace the fixed delay with the native-storage persistence signal (chatUpdatesPublisher).
        guard deactivationDelay > 0 else { return deactivate(tab) }
        DispatchQueue.main.asyncAfter(deadline: .now() + deactivationDelay) { [weak self] in
            self?.deactivate(tab)
        }
    }

    private func deactivate(_ tab: Tab) {
        activeTabs.remove(tab)
        changesSubject.send()
    }

    private func resolveTab(from note: Notification) -> Tab? {
        guard let webView = note.object as? WKWebView else { return nil }
        return tabForWebView(webView)
    }
}
