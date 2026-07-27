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

import AppKit

/// Hands a Prompt Bar prompt to Duck.ai.
@MainActor
protocol PromptBarPromptSubmitting {

    /// - Parameter screen: The screen the Prompt Bar is on. A browser window there is reused;
    ///   otherwise a new window is opened, so the chat never appears on a display the user isn't looking at.
    func submit(prompt: String, preferringWindowOn screen: NSScreen?)
}

/// The window properties that decide whether a browser window can host a submitted prompt.
/// A protocol so the rule can be tested without real windows.
@MainActor
protocol PromptBarHostWindow {
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }

    /// Whether the window is on the Space the user is currently viewing.
    var isOnActiveSpace: Bool { get }

    /// Frame of the display showing most of the window, or `nil` when the window is offscreen.
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

    init(aiChatTabOpener: AIChatTabOpening, windowControllersManager: WindowControllersManagerProtocol) {
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
    }

    func submit(prompt: String, preferringWindowOn screen: NSScreen?) {
        if let windowController = windowToReuse(on: screen) {
            aiChatTabOpener.openAIChatTab(withQuery: prompt, inNewTabOf: windowController)
        } else if let visibleFrame = screen?.visibleFrame {
            // Placed explicitly: an unplaced new window cascades off the last key window, which is
            // how it would end up back on the display the user just walked away from.
            aiChatTabOpener.openAIChatTab(withQuery: prompt, inNewWindowAt: Self.newWindowDroppingPoint(in: visibleFrame))
        } else {
            aiChatTabOpener.openAIChatTab(with: .query(prompt, shouldAutoSubmit: true), behavior: .newWindow(selected: true))
        }
    }

    /// Top-center point for a new window, which is what `droppingPoint` means: horizontally centered
    /// on the target display and flush with the top of its visible area.
    static func newWindowDroppingPoint(in visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.midX, y: visibleFrame.maxY)
    }

    /// The most recently focused eligible window, so a screen showing several windows reuses the one
    /// the user last worked in. `lastKeyMainWindowController(where:)` already excludes popups.
    private func windowToReuse(on screen: NSScreen?) -> MainWindowController? {
        let targetScreenFrame = screen?.frame
        return windowControllersManager.lastKeyMainWindowController { windowController in
            guard let window = windowController.window else { return false }
            return Self.canHostPrompt(window, submittedFromScreenFrame: targetScreenFrame)
        }
    }

    /// A window qualifies when it is actually on screen, on the Space being viewed, and on the
    /// display the prompt came from. With an unknown source display, any on-screen window qualifies —
    /// better to reuse a window than to open one the user may not have wanted.
    static func canHostPrompt(_ window: PromptBarHostWindow, submittedFromScreenFrame screenFrame: NSRect?) -> Bool {
        guard window.isVisible, !window.isMiniaturized, window.isOnActiveSpace else { return false }
        guard let screenFrame else { return true }
        return window.screenFrame == screenFrame
    }
}
