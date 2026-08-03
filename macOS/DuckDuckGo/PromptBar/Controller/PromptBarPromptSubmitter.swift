//
//  PromptBarPromptSubmitter.swift
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

import AIChat
import AppKit

/// Routes what the Prompt Bar produces into a browser window, preferring the display it opened on.
@MainActor
protocol PromptBarPromptSubmitting {

    /// `query` seeds the tab; `payload` is re-applied once it's open — the address bar's two-step.
    func submit(query: String, payload: AIChatNativePrompt?, preferringWindowOn screen: NSScreen?)

    /// Resolves the same window a prompt would, so an active session there is focused rather than
    /// a second one opened.
    func openVoiceSession(preferringWindowOn screen: NSScreen?)

    func open(url: URL, preferringWindowOn screen: NSScreen?)
}

/// A protocol so the eligibility rule tests without real windows.
@MainActor
protocol PromptBarHostWindow {
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }
    var isOnActiveSpace: Bool { get }

    /// Frames identify displays: two screens can never share one in global coordinates.
    var screenFrame: NSRect? { get }
}

extension NSWindow: PromptBarHostWindow {
    var screenFrame: NSRect? { screen?.frame }
}

@MainActor
final class PromptBarPromptSubmitter: PromptBarPromptSubmitting {

    private let aiChatTabOpener: AIChatTabOpening
    private let windowControllersManager: WindowControllersManagerProtocol
    private let promptHandler: AIChatPromptHandler

    init(aiChatTabOpener: AIChatTabOpening,
         windowControllersManager: WindowControllersManagerProtocol,
         promptHandler: AIChatPromptHandler = .shared) {
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
        self.promptHandler = promptHandler
    }

    func submit(query: String, payload: AIChatNativePrompt?, preferringWindowOn screen: NSScreen?) {
        AIChatConversationSourceHandler.shared.setData(.promptBar)
        if let windowController = windowToReuse(on: screen) {
            aiChatTabOpener.openAIChatTab(withQuery: query, inNewTabOf: windowController)
        } else if let visibleFrame = screen?.visibleFrame {
            // Placed explicitly: an unplaced window cascades off the last key window, i.e. back onto its display.
            aiChatTabOpener.openAIChatTab(withQuery: query, inNewWindowAt: Self.newWindowDroppingPoint(in: visibleFrame))
        } else {
            aiChatTabOpener.openAIChatTab(with: .query(query, shouldAutoSubmit: true), behavior: .newWindow(selected: true))
        }

        // Every opener above seeds a plain query, so the payload has to land after them.
        if let payload {
            promptHandler.setData(payload)
        }

        // The bar never activates the app, so submitting is what brings the browser forward.
        NSApp.activate(ignoringOtherApps: true)
    }

    func openVoiceSession(preferringWindowOn screen: NSScreen?) {
        let sourceCollection = windowToReuse(on: screen)?.mainViewController.tabCollectionViewModel
        AIChatConversationSourceHandler.shared.setData(.voice)
        aiChatTabOpener.openVoiceSession(inSourceCollection: sourceCollection, behavior: .newTab(selected: true))
        NSApp.activate(ignoringOtherApps: true)
    }

    func open(url: URL, preferringWindowOn screen: NSScreen?) {
        if let windowController = windowToReuse(on: screen) {
            // `show(url:)` targets the last key window, so promote the screen-scoped one before asking.
            windowController.window?.makeKeyAndOrderFront(nil)
            showInLastKeyWindow(url)
        } else if let visibleFrame = screen?.visibleFrame {
            // As in `submit(query:)`: `show(url:)`'s own fallback cascades onto the last key window.
            WindowsManager.openNewWindow(with: url,
                                         source: .userEntered(url.absoluteString),
                                         droppingPoint: Self.newWindowDroppingPoint(in: visibleFrame))
        } else {
            showInLastKeyWindow(url)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func showInLastKeyWindow(_ url: URL) {
        windowControllersManager.show(url: url,
                                      source: .userEntered(url.absoluteString),
                                      newTab: true,
                                      selected: true)
    }

    /// `droppingPoint` is a window's top-center: centered on the display, flush with its visible top.
    static func newWindowDroppingPoint(in visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.midX, y: visibleFrame.maxY)
    }

    private func windowToReuse(on screen: NSScreen?) -> MainWindowController? {
        let targetScreenFrame = screen?.frame
        return windowControllersManager.lastKeyMainWindowController { windowController in
            guard let window = windowController.window else { return false }
            return Self.canHostPrompt(window, submittedFromScreenFrame: targetScreenFrame)
        }
    }

    static func canHostPrompt(_ window: PromptBarHostWindow, submittedFromScreenFrame screenFrame: NSRect?) -> Bool {
        guard window.isVisible, !window.isMiniaturized, window.isOnActiveSpace else { return false }
        guard let screenFrame else { return true }
        return window.screenFrame == screenFrame
    }
}
