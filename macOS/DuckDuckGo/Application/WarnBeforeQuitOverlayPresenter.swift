//
//  WarnBeforeQuitOverlayPresenter.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import QuartzCore
import SwiftUI

/// Presents and manages the quit confirmation overlay UI.
///
/// Observes state changes from WarnBeforeQuitManager and updates the UI accordingly.
@MainActor
final class WarnBeforeQuitOverlayPresenter {

    // MARK: - Properties

    var overlayWindow: NSWindow?
    private let viewModel: WarnBeforeQuitViewModel
    private var observationTask: Task<Void, Never>?
    private var progressDelayTask: Task<Void, Never>?
    /// Is completing via second shortcut press (shows quick progress animation) vs button click (no animation)
    private var isCompletingViaSecondPress = false

    let windowProvider: @MainActor () -> NSWindow?
    let anchorViewProvider: (@MainActor () -> NSView?)?

    // MARK: - Initialization

    init(action: ConfirmationAction = .quit,
         startupPreferences: StartupPreferences? = nil,
         onDontAskAgain: (() -> Void)? = nil,
         onHoverChange: ((Bool) -> Void)? = nil,
         windowProvider: @MainActor @escaping () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow },
         anchorViewProvider: (@MainActor () -> NSView?)? = nil) {
        self.viewModel = WarnBeforeQuitViewModel(
            action: action,
            startupPreferences: startupPreferences,
            onDontAskAgain: onDontAskAgain
        )
        self.windowProvider = windowProvider
        self.anchorViewProvider = anchorViewProvider
        self.viewModel.onHoverChange = { [weak self] isHovering in
            onHoverChange?(isHovering)
            // Enable/disable mouse events passing through the window to allow clicking the underlying content view
            self?.overlayWindow?.ignoresMouseEvents = !isHovering
        }
    }

    /// Subscribes to the manager's state stream. Keeps the presenter alive as long as the stream is active.
    func subscribe(to stateStream: AsyncStream<WarnBeforeQuitManager.State>) {
        observationTask = Task { @MainActor in
            for await state in stateStream {
                self.handle(state: state)
            }
        }
    }

    deinit {
        observationTask?.cancel()
        progressDelayTask?.cancel()
    }

    // MARK: - Private

    private func handle(state: WarnBeforeQuitManager.State) {
        switch state {
        case .idle:
            isCompletingViaSecondPress = false

        case .holding:
            // Show overlay and start progress animation to 100% after threshold
            isCompletingViaSecondPress = false
            show()
            // Delay progress animation to prevent showing on quick taps
            progressDelayTask?.cancel()
            progressDelayTask = Task { @MainActor [weak viewModel] in
                try? await Task.sleep(interval: WarnBeforeQuitManager.Constants.progressThreshold)
                // Only start animation if task wasn't cancelled and viewModel still exists
                guard !Task.isCancelled, let viewModel = viewModel else { return }
                let duration = WarnBeforeQuitManager.Constants.requiredHoldDuration - WarnBeforeQuitManager.Constants.progressThreshold
                viewModel.startProgress(duration: duration)
            }

        case .waitingForSecondPress:
            // Stop progress animation and reset
            progressDelayTask?.cancel()
            progressDelayTask = nil
            isCompletingViaSecondPress = false
            // Reset progress with quick spring animation (0.3 seconds)
            viewModel.resetProgress()

        case .completing:
            // Cancel any pending delay task
            progressDelayTask?.cancel()
            progressDelayTask = nil
            isCompletingViaSecondPress = true
            // Quick animation to 100% on second press
            viewModel.startProgressQuick()

        case .completed(let shouldProceed):
            // Cancel any pending progress animation
            progressDelayTask?.cancel()
            progressDelayTask = nil
            // Hide after a brief delay to let final state render
            Task {
                // Only set progress to 100% if action is proceeding via second press (not button click)
                if shouldProceed && isCompletingViaSecondPress {
                    viewModel.completeProgress()
                }
                isCompletingViaSecondPress = false
                // Wait for UI to render the final state
                try? await Task.sleep(interval: 0.033) // 33ms (2 frames at 60fps)
                hide()
            }
            // Just hide - don't call terminate, the decider framework handles that
        }
    }

    private func show() {
        guard let keyWindow = windowProvider() else { return }

        if overlayWindow == nil {
            overlayWindow = createOverlayWindow()
        }

        guard let overlayWindow else { return }

        // Make window fill the parent window
        let windowFrame = keyWindow.frame
        overlayWindow.setFrame(windowFrame, display: true)

        // Calculate balloon position and pass to view
        let balloonPosition: CGPoint
        if let anchorView = anchorViewProvider?(), let window = anchorView.window {
            // Get anchor view's frame in screen coordinates
            let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorFrameInScreen = window.convertToScreen(anchorFrameInWindow)

            // Convert to overlay window coordinates (AppKit coordinates, bottom-left origin)
            let anchorFrameInOverlay = overlayWindow.convertFromScreen(anchorFrameInScreen)

            // Convert to SwiftUI coordinates (top-left origin)
            // In AppKit: y increases upward, in SwiftUI: y increases downward
            balloonPosition = CGPoint(
                x: anchorFrameInOverlay.midX,
                y: overlayWindow.frame.height - anchorFrameInOverlay.minY
            )
        } else {
            // Default: Position at top center (already in SwiftUI coordinates)
            balloonPosition = CGPoint(
                x: overlayWindow.frame.width / 2,
                y: WarnBeforeQuitView.Constants.quitPanelTopOffset
            )
        }

        viewModel.balloonAnchorPosition = balloonPosition

        // Add as child window to ensure it stays on top
        keyWindow.addChildWindow(overlayWindow, ordered: .above)

        // Always animate in (reset alpha to 0 first)
        overlayWindow.alphaValue = 0
        animateIn(window: overlayWindow)
    }

    private func hide() {
        guard let overlayWindow else { return }

        // Animate out with spring animation
        animateOut(window: overlayWindow) { [weak self] in
            // Clear content view to prevent shadow artifacts
            overlayWindow.contentView = nil

            // Order out asynchronously to allow content view cleanup
            DispatchQueue.main.async {
                self?.overlayWindow = nil
                overlayWindow.parent?.removeChildWindow(overlayWindow)
                overlayWindow.orderOut(nil)
                // Reset progress after window is hidden
                self?.viewModel.resetProgress()
            }
        }
    }

    // MARK: - Animations

    /// Animates window in with fade animation
    /// - Parameters:
    ///   - window: The window to animate
    private func animateIn(window: NSWindow) {
        // Window frame is already set (fills parent), just fade in
        window.alphaValue = 0

        // Show window before animating
        window.makeKeyAndOrderFront(nil)

        // Simple fade-in animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            window.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }

    /// Animates window out with fade animation
    /// - Parameters:
    ///   - window: The window to animate
    ///   - completion: Called after animation finishes
    private func animateOut(window: NSWindow, completion: @escaping () -> Void) {
        // Simple fade-out animation (window stays full-size, only opacity changes)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)

            window.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    private func createOverlayWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.level = .floating
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.alphaValue = 0 // Start invisible for animation
        // Set barely-visible background to prevent shadow clipping when scrolling content below
        window.backgroundColor = NSColor(white: 0, alpha: 0.01)
        // Start ignoring mouse events to allow click-through; toggled on hover (see `viewModel.onHoverChange` in `init`)
        window.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: WarnBeforeQuitView(viewModel: viewModel))
        window.contentView = hostingView

        return window
    }

}
