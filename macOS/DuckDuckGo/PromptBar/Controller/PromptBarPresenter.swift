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

/// Owns the Prompt Bar window and the dismissal policy: Escape, submit, and losing key status —
/// the last of which is suppressed while the content has a menu or file picker up.
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

    /// `screenProvider` is resolved in the body rather than as a default value: default parameter
    /// values are evaluated in a nonisolated context, and the provider is main-actor isolated.
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

        // The bar is a keyboard-first surface, so the app has to come forward to receive typing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Only meaningful once the window is key, so it follows the ordering above.
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

    /// Clicking outside dismisses, but a tool menu or `NSOpenPanel` also takes key away — those
    /// must not close the bar the user is still filling in.
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

        // Keep the top edge pinned so the bar grows downwards as the prompt gets longer.
        var frame = window.frame
        let top = frame.maxY
        frame.size.height = size.height
        frame.origin.y = top - size.height
        window.setFrame(frame, display: true, animate: false)
    }
}
