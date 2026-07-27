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

@MainActor
protocol PromptBarPromptSubmitting {

    func submit(prompt: String, preferringWindowOn screen: NSScreen?)
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

    init(aiChatTabOpener: AIChatTabOpening, windowControllersManager: WindowControllersManagerProtocol) {
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
    }

    func submit(prompt: String, preferringWindowOn screen: NSScreen?) {
        if let windowController = windowToReuse(on: screen) {
            aiChatTabOpener.openAIChatTab(withQuery: prompt, inNewTabOf: windowController)
        } else if let visibleFrame = screen?.visibleFrame {
            // Placed explicitly: an unplaced window cascades off the last key window, i.e. back onto its display.
            aiChatTabOpener.openAIChatTab(withQuery: prompt, inNewWindowAt: Self.newWindowDroppingPoint(in: visibleFrame))
        } else {
            aiChatTabOpener.openAIChatTab(with: .query(prompt, shouldAutoSubmit: true), behavior: .newWindow(selected: true))
        }

        // The bar never activates the app, so submitting is what brings the browser forward.
        NSApp.activate(ignoringOtherApps: true)
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
