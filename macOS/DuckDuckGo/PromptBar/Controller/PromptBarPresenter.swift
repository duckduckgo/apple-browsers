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
import PixelKit

/// Which entry point put the bar on screen. Each reports its own pixel, and re-triggering the same
/// one while the bar is up is what closes it.
enum PromptBarPresentationSource: Equatable, CaseIterable {
    case keyboardShortcut
    case menuBarIcon

    var shownPixel: PromptBarPixel {
        switch self {
        case .keyboardShortcut: .shownFromShortcut
        case .menuBarIcon: .shownFromMenuBarIcon
        }
    }

    var toggleDismissReason: PromptBarDismissReason {
        switch self {
        case .keyboardShortcut: .shortcutToggle
        case .menuBarIcon: .menuBarIconToggle
        }
    }
}

/// Why the bar closed. Only the reasons that leave the prompt unsent are reported — the submit
/// pixels already cover the rest.
enum PromptBarDismissReason: Equatable {
    /// A prompt, URL or voice session was handed off.
    case submission
    case escape
    case clickOutside
    case shortcutToggle
    case menuBarIconToggle

    var cancellation: PromptBarCancellationReason? {
        switch self {
        case .submission: nil
        case .escape: .escape
        case .clickOutside: .clickOutside
        case .shortcutToggle: .shortcutToggle
        case .menuBarIconToggle: .menuBarIcon
        }
    }
}

@MainActor
protocol PromptBarPresenting: AnyObject {
    var isVisible: Bool { get }
    func show(source: PromptBarPresentationSource)
    func dismiss(reason: PromptBarDismissReason)
    func toggle(source: PromptBarPresentationSource)
}

@MainActor
final class PromptBarPresenter: PromptBarPresenting {

    private let content: PromptBarContentHosting
    private let screenProvider: PromptBarScreenProviding
    private let makeWindow: (NSRect) -> PromptBarWindow
    private let firePixel: (PromptBarPixel) -> Void

    private var window: PromptBarWindow?
    private var resignKeyCancellable: AnyCancellable?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // `screenProvider` has no default value: defaults are evaluated nonisolated, and the provider is @MainActor.
    init(content: PromptBarContentHosting,
         screenProvider: PromptBarScreenProviding? = nil,
         makeWindow: @escaping (NSRect) -> PromptBarWindow = { PromptBarWindow(contentRect: $0) },
         firePixel: @escaping (PromptBarPixel) -> Void = { PixelKit.fire($0, frequency: .dailyAndCount, includeAppVersionParameter: true) }) {
        self.content = content
        self.screenProvider = screenProvider ?? MouseLocationScreenProvider()
        self.makeWindow = makeWindow
        self.firePixel = firePixel

        self.content.onSubmit = { [weak self] in
            self?.dismiss(reason: .submission)
        }
        self.content.onPreferredWindowContentSizeChanged = { [weak self] size in
            self?.resizeWindow(toContentSize: size)
        }
    }

    func toggle(source: PromptBarPresentationSource) {
        if isVisible {
            dismiss(reason: source.toggleDismissReason)
        } else {
            show(source: source)
        }
    }

    func show(source: PromptBarPresentationSource) {
        content.prepareForPresentation()

        let window = existingWindowOrNew()
        window.setFrame(PromptBarPlacement.frame(forContentHeight: content.preferredWindowContentSize.height,
                                                 in: screenProvider.targetVisibleFrame),
                        display: false)

        // No `NSApp.activate`: it would raise the browser's windows above whatever the user has in front.
        window.orderFrontRegardless()
        window.makeKey()
        // First responder only sticks once the window is key.
        content.focusPromptEditor()
        // Per presentation, not per window: `dismiss()` tears this down.
        subscribeToResignKey(of: window)

        firePixel(source.shownPixel)
    }

    func dismiss(reason: PromptBarDismissReason) {
        // Visibility, not just existence: submitting reports through two delegate callbacks and so
        // asks to dismiss twice, and `resetAfterDismissal` must not run against a torn-down bar.
        guard let window, window.isVisible else { return }
        // Read before `resetAfterDismissal()` clears the draft.
        let hadText = content.hasPromptText
        resignKeyCancellable = nil
        window.orderOut(nil)
        content.resetAfterDismissal()

        if let cancellation = reason.cancellation {
            firePixel(.dismissedWithoutSubmission(reason: cancellation, hadText: hadText))
        }
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
            self?.dismiss(reason: .escape)
        }
        self.window = window
        return window
    }

    /// Clicking outside dismisses — but a tool menu or `NSOpenPanel` also takes key away, and must not.
    private func subscribeToResignKey(of window: PromptBarWindow) {
        resignKeyCancellable = NotificationCenter.default
            .publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in
                guard let self, !self.content.isPresentingAuxiliaryUI else { return }
                self.dismiss(reason: .clickOutside)
            }
    }

    private func resizeWindow(toContentSize size: NSSize) {
        guard let window else { return }

        var frame = window.frame
        let top = frame.maxY
        frame.size.height = size.height
        frame.origin.y = top - size.height
        window.setFrame(frame, display: true, animate: false)
    }
}
