//
//  RemoteMessageImpressionReporter.swift
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
import UIKit

@MainActor
final class RemoteMessageImpressionReporter {

    static let remoteMessageSurfaceDidChange = Notification.Name("NewTabPageRemoteMessageSurfaceDidChange")

    struct Snapshot {
        let tabID: String
        let messageID: String
        let window: UIWindow
        let surfaceRoot: UIViewController?
        let searchDismissSurface: UIViewController?
    }

    private struct VisibleMessage: Equatable {
        let tabID: String
        let messageID: String
    }

    private let contentDidChangePublisher: AnyPublisher<Void, Never>
    private let hasCurrentMessage: () -> Bool
    private let snapshot: () -> Snapshot?
    private let reportVisibleMessage: (String) -> Bool
    private let messageDidStopBeingVisible: (String) -> Void
    private let notificationCenter: NotificationCenter
    private let messageVisibilityOverride: ((String, UIViewController, UIWindow) -> Bool)?

    private var currentVisibleMessage: VisibleMessage?
    private var visibilityCancellables = Set<AnyCancellable>()
    private var inputCancellables = Set<AnyCancellable>()
    private var isCheckScheduled = false
    private var isBrowserPresented = false

    init(contentDidChangePublisher: AnyPublisher<Void, Never>,
         hasCurrentMessage: @escaping () -> Bool,
         snapshot: @escaping () -> Snapshot?,
         reportVisibleMessage: @escaping (String) -> Bool,
         messageDidStopBeingVisible: @escaping (String) -> Void,
         notificationCenter: NotificationCenter = .default,
         messageVisibilityOverride: ((String, UIViewController, UIWindow) -> Bool)? = nil) {
        self.contentDidChangePublisher = contentDidChangePublisher
        self.hasCurrentMessage = hasCurrentMessage
        self.snapshot = snapshot
        self.reportVisibleMessage = reportVisibleMessage
        self.messageDidStopBeingVisible = messageDidStopBeingVisible
        self.notificationCenter = notificationCenter
        self.messageVisibilityOverride = messageVisibilityOverride
    }

    func observeVisibilityChanges() {
        let signals = [Self.remoteMessageSurfaceDidChange,
                       UIApplication.didBecomeActiveNotification,
                       UIWindow.didBecomeKeyNotification,
                       UIWindow.didResignKeyNotification]
        for name in signals {
            notificationCenter.publisher(for: name)
                .sink { [weak self] _ in self?.scheduleCheck() }
                .store(in: &visibilityCancellables)
        }
        contentDidChangePublisher
            .sink { [weak self] _ in self?.scheduleCheck() }
            .store(in: &visibilityCancellables)
    }

    func observeInputVisibility(_ coordinator: UnifiedToggleInputCoordinator?) {
        inputCancellables.removeAll()
        guard let coordinator else { return }
        coordinator.modeChangePublisher
            .sink { [weak self] mode in self?.inputModeDidChange(mode) }
            .store(in: &inputCancellables)
        coordinator.textChangePublisher
            .sink { [weak self] _ in self?.scheduleCheck() }
            .store(in: &inputCancellables)
        coordinator.intentPublisher
            .sink { [weak self] _ in self?.scheduleCheck() }
            .store(in: &inputCancellables)
    }

    func browserDidAppear() {
        isBrowserPresented = true
        scheduleCheck()
    }

    func browserWillDisappear() {
        isBrowserPresented = false
        reset()
    }

    func inputModeDidChange(_ mode: TextEntryMode) {
        if mode == .aiChat { reset() }
        scheduleCheck()
    }

    func reset() {
        guard let currentVisibleMessage else { return }
        self.currentVisibleMessage = nil
        messageDidStopBeingVisible(currentVisibleMessage.messageID)
    }

    func scheduleCheck() {
        guard hasCurrentMessage() || currentVisibleMessage != nil else { return }
        guard !isCheckScheduled else { return }
        isCheckScheduled = true
        // Mode and content publishers can precede the corresponding hierarchy changes.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isCheckScheduled = false
            reportIfVisible()
        }
    }

    private func reportIfVisible() {
        guard isBrowserPresented, let snapshot = snapshot() else {
            reset()
            return
        }

        let observedMessage = VisibleMessage(tabID: snapshot.tabID, messageID: snapshot.messageID)
        guard let surfaceRoot = snapshot.surfaceRoot,
              isMessageVisible(snapshot.messageID, in: surfaceRoot, window: snapshot.window) else {
            // Back fades the focused Search NTP while the same card remains on the resting NTP.
            // Keep the current message only; this fallback must never report a new showing.
            if currentVisibleMessage != observedMessage || !isVisibleDuringSearchDismiss(snapshot) {
                reset()
            }
            return
        }
        guard currentVisibleMessage != observedMessage else { return }
        reset()
        // Reserve before reporting: eligibility reconciliation can synchronously publish content.
        currentVisibleMessage = observedMessage
        if !reportVisibleMessage(snapshot.messageID) {
            currentVisibleMessage = nil
        }
    }

    private func isVisibleDuringSearchDismiss(_ snapshot: Snapshot) -> Bool {
        guard let surface = snapshot.searchDismissSurface else { return false }
        return isMessageVisible(snapshot.messageID, in: surface, window: snapshot.window)
    }

    private func isMessageVisible(_ messageID: String, in controller: UIViewController, window: UIWindow) -> Bool {
        messageVisibilityOverride?(messageID, controller, window) ?? containsVisibleRemoteMessage(messageID, in: controller, window: window)
    }

    private func containsVisibleRemoteMessage(_ messageID: String, in controller: UIViewController, window: UIWindow) -> Bool {
        guard controller.presentedViewController == nil,
              let surfaceView = controller.viewIfLoaded,
              surfaceView.window === window else { return false }
        var ancestor: UIView? = surfaceView
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else { return false }
            ancestor = view.superview
        }
        guard surfaceView.convert(surfaceView.bounds, to: window).intersects(window.bounds) else { return false }
        if let page = controller as? NewTabPageViewController {
            return page.isRemoteMessageSurfacePresented && page.hasAppearedRemoteMessage(withID: messageID)
        }
        return controller.children.contains { containsVisibleRemoteMessage(messageID, in: $0, window: window) }
    }
}
