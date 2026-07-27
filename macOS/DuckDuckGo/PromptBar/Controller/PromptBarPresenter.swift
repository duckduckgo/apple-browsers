//
//  PromptBarPresenter.swift
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

import AppKit
import Combine

/// Shows and hides the floating Prompt Bar.
@MainActor
protocol PromptBarPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func dismiss()
    func toggle()
}

/// Owns the Prompt Bar window and its dismissal policy.
@MainActor
final class PromptBarPresenter: PromptBarPresenting {

    private let content: PromptBarContentHosting
    private let screenProvider: PromptBarScreenProviding
    private let makeWindow: (NSRect) -> PromptBarWindow

    private var window: PromptBarWindow?
    private var resignKeyCancellable: AnyCancellable?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // `screenProvider` has no default value: defaults are evaluated nonisolated, and the provider is @MainActor.
    init(content: PromptBarContentHosting,
         screenProvider: PromptBarScreenProviding? = nil,
         makeWindow: @escaping (NSRect) -> PromptBarWindow = { PromptBarWindow(contentRect: $0) }) {
        self.content = content
        self.screenProvider = screenProvider ?? MouseLocationScreenProvider()
        self.makeWindow = makeWindow

        self.content.onSubmit = { [weak self] in
            self?.dismiss()
        }
        self.content.onPreferredWindowContentSizeChanged = { [weak self] size in
            self?.resizeWindow(toContentSize: size)
        }
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        content.prepareForPresentation()

        let window = existingWindowOrNew()
        window.setFrame(PromptBarPlacement.frame(forContentHeight: content.preferredWindowContentSize.height,
                                                 in: screenProvider.targetVisibleFrame),
                        display: false)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // First responder only sticks once the window is key.
        content.focusPromptEditor()
    }

    func dismiss() {
        guard let window else { return }
        resignKeyCancellable = nil
        window.orderOut(nil)
        content.resetAfterDismissal()
    }

    private func existingWindowOrNew() -> PromptBarWindow {
        if let window {
            return window
        }

        let initialFrame = PromptBarPlacement.frame(forContentHeight: content.preferredWindowContentSize.height,
                                                    in: screenProvider.targetVisibleFrame)
        let window = makeWindow(initialFrame)
        window.contentViewController = content.viewController
        window.onCancel = { [weak self] in
            self?.dismiss()
        }
        subscribeToResignKey(of: window)
        self.window = window
        return window
    }

    /// Clicking outside dismisses — but a tool menu or `NSOpenPanel` also takes key away, and must not.
    private func subscribeToResignKey(of window: PromptBarWindow) {
        resignKeyCancellable = NotificationCenter.default
            .publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in
                guard let self, !self.content.isPresentingAuxiliaryUI else { return }
                self.dismiss()
            }
    }

    private func resizeWindow(toContentSize size: NSSize) {
        guard let window, window.isVisible else { return }

        // Pin the top edge so the bar grows downwards.
        var frame = window.frame
        let top = frame.maxY
        frame.size.height = size.height
        frame.origin.y = top - size.height
        window.setFrame(frame, display: true, animate: false)
    }
}
