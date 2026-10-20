//
//  DaxPetCoordinator.swift
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
import Combine
import ConcurrencyExtensions
import SwiftUI

/// Puts Dax on the desktop while the setting is on, and keeps him standing where he was left.
@MainActor
final class DaxPetCoordinator: NSObject {

    private let preferences: DaxPetPreferences
    private var persistor: DaxPetPreferencesPersistor
    private let submitter: DaxPetPromptSubmitting

    private var window: DaxPetWindow?
    private var model: DaxPetViewModel?
    private var enabledCancellable: AnyCancellable?
    private var pointerTimer: Timer?
    private var isPointerOverCharacter = false

    init(preferences: DaxPetPreferences, persistor: DaxPetPreferencesPersistor, submitter: DaxPetPromptSubmitting) {
        self.preferences = preferences
        self.persistor = persistor
        self.submitter = submitter
    }

    func start() {
        enabledCancellable = preferences.isEffectivelyEnabledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.show()
                } else {
                    self?.dismiss()
                }
            }
    }

    private func show() {
        guard window == nil else { return }

        let model = DaxPetViewModel(submitter: submitter)
        let window = DaxPetWindow(contentRect: NSRect(origin: .zero, size: DaxPetView.Metrics.windowSize))
        window.contentView = NSHostingView(rootView: DaxPetView(model: model))
        window.delegate = self
        window.onCancel = { [weak model] in model?.endComposing() }

        model.onHide = { [weak self] in self?.preferences.isEnabled = false }
        model.onNeedsKeyboard = { [weak window] in window?.makeKey() }
        model.caretLocation = { [weak window] promptWidth in
            guard let frame = window?.frame else { return nil }
            let fieldWidth = DaxPetView.Metrics.composingWidth
            let fieldMinX = frame.midX - fieldWidth / 2
            let fieldMidY = frame.minY + DaxPetView.Metrics.padding + DaxPetView.Metrics.controlsHeight / 2
            return NSPoint(x: fieldMinX + DaxPetView.Metrics.promptLeadingInset + min(promptWidth, fieldWidth - 60), y: fieldMidY)
        }
        model.character.onClick = { [weak model] in model?.characterClicked() }
        model.character.onDragEnded = { [weak self] in self?.savePosition() }

        self.window = window
        self.model = model

        let position = initialPosition()
        window.setFrameOrigin(NSPoint(x: (position.x - DaxPetView.Metrics.windowSize.width / 2).rounded(), y: position.y))
        window.orderFrontRegardless()
        startTrackingPointer()
        model.sayHello()
    }

    private func dismiss() {
        model?.endComposing()
        window?.orderOut(nil)
        window?.close()
        window = nil
        model = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    /// The window is mostly empty space: it only takes clicks over Dax, his controls and his speech bubble.
    private func startTrackingPointer() {
        let timer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeMainThread { self?.updatePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        updatePointer()
    }

    private func updatePointer() {
        guard let window, let model else { return }
        let mouse = NSEvent.mouseLocation
        let point = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)

        let isOverCharacter = DaxPetView.Metrics.characterFrame().contains(point)
        var interactiveFrames = [DaxPetView.Metrics.characterFrame(), DaxPetView.Metrics.controlsFrame(isComposing: model.isComposing)]
        if model.speech != nil {
            interactiveFrames.append(DaxPetView.Metrics.bubbleFrame())
        }
        // A press in progress (e.g. dragging Dax) keeps its window.
        let isInteractive = NSEvent.pressedMouseButtons != 0 && !window.ignoresMouseEvents
            || interactiveFrames.contains { $0.contains(point) }
        if window.ignoresMouseEvents == isInteractive {
            window.ignoresMouseEvents = !isInteractive
        }

        if isOverCharacter, !isPointerOverCharacter {
            model.characterHovered()
        }
        isPointerOverCharacter = isOverCharacter
    }

    private func savePosition() {
        guard let frame = window?.frame else { return }
        persistor.position = CGPoint(x: frame.midX, y: frame.minY)
    }

    /// Where he was left, as long as that's still on a screen; otherwise the bottom-right corner.
    private func initialPosition() -> CGPoint {
        if let saved = persistor.position,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(saved) }) {
            return saved
        }
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visibleFrame.maxX - 120, y: visibleFrame.minY + 24)
    }
}

extension DaxPetCoordinator: NSWindowDelegate {

    func windowDidResignKey(_ notification: Notification) {
        model?.keyboardFocusLost()
    }
}

/// Floats above everything, on every Space, without ever activating the browser by itself.
final class DaxPetWindow: NSPanel {

    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class DaxPetPromptSubmitter: DaxPetPromptSubmitting {

    private let aiChatTabOpener: AIChatTabOpening

    init(aiChatTabOpener: AIChatTabOpening) {
        self.aiChatTabOpener = aiChatTabOpener
    }

    func submit(prompt: String) {
        aiChatTabOpener.openAIChatTab(with: .query(prompt, shouldAutoSubmit: true), behavior: .newTab(selected: true))
        // Dax never activates the app, so handing off is what brings the browser forward.
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDuckAI() {
        aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
        NSApp.activate(ignoringOtherApps: true)
    }
}
