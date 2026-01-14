//
//  OverlayPresenter.swift
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
final class OverlayPresenter {

    // MARK: - Properties

    private(set) var overlayWindow: NSWindow?
    private let viewModel: WarnBeforeQuitViewModel
    private var observationTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    let windowProvider: @MainActor () -> NSWindow?

    // MARK: - Initialization

    init(startupPreferences: StartupPreferences?,
         onDontAskAgain: @escaping () -> Void,
         onHoverChange: @escaping (Bool) -> Void,
         windowProvider: @MainActor @escaping () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow }) {
        self.viewModel = WarnBeforeQuitViewModel(startupPreferences: startupPreferences)
        self.windowProvider = windowProvider
        self.viewModel.onDontAskAgain = onDontAskAgain
        self.viewModel.onHoverChange = onHoverChange
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
        progressTask?.cancel()
    }

    // MARK: - Private

    private func handle(state: WarnBeforeQuitManager.State) {
        switch state {
        case .idle:
            break

        case .holding(let startTime, let targetTime):
            show()
            startProgressAnimation(startTime: startTime, targetTime: targetTime)

        case .waitingForSecondPress:
            // Show overlay if not already shown (in case key was released immediately)
            show()
            // Stop progress animation and reset
            progressTask?.cancel()
            viewModel.resetProgress()

        case .completed:
            hide()
            // Just hide - don't call terminate, the decider framework handles that
        }
    }

    private func show() {
        guard let keyWindow = windowProvider() else { return }

        if overlayWindow == nil {
            overlayWindow = createOverlayWindow()
        }

        guard let overlayWindow else { return }

        // Position overlay at top center of the key window
        let windowFrame = keyWindow.frame
        let overlaySize = CGSize(width: 520, height: 90)
        let overlayOrigin = CGPoint(
            x: windowFrame.midX - overlaySize.width / 2,
            y: windowFrame.maxY - overlaySize.height - 80
        )

        overlayWindow.setFrame(CGRect(origin: overlayOrigin, size: overlaySize), display: true)

        // Add as child window to ensure it stays on top
        keyWindow.addChildWindow(overlayWindow, ordered: .above)
        overlayWindow.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        progressTask?.cancel()
        viewModel.resetProgress()

        if let parentWindow = overlayWindow?.parent {
            parentWindow.removeChildWindow(overlayWindow!)
        }
        overlayWindow?.orderOut(nil)
    }

    private func createOverlayWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: WarnBeforeQuitView(viewModel: viewModel))
        window.contentView = hostingView

        return window
    }

    private func startProgressAnimation(startTime: TimeInterval, targetTime: TimeInterval) {
        progressTask?.cancel()

        let duration = targetTime - startTime

        progressTask = Task {
            while !Task.isCancelled {
                let now = Date().timeIntervalSinceReferenceDate
                let elapsed = now - startTime
                let progress = CGFloat(max(0, min(1, elapsed / duration)))

                // Check cancellation before updating
                guard !Task.isCancelled else { break }
                viewModel.updateProgress(progress)

                if progress >= 1.0 {
                    break
                }

                try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
            }
        }
    }
}
