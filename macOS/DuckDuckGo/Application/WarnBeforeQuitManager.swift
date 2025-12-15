//
//  WarnBeforeQuitManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SwiftUI
import QuartzCore

// MARK: - State Machine

enum QuitConfirmationState: Equatable {
    case idle
    case active
    case holding(targetTime: CFTimeInterval)
    case completed(shouldQuit: Bool)
}

/// Manages the "Warn Before Quitting" feature that prevents accidental app termination.
///
/// When CMD+Q is pressed, this manager shows an overlay prompting the user to either:
/// - Hold CMD+Q for 1 second to quit
/// - Press CMD+Q again to quit
/// - Click "Don't ask again" to disable the feature
@MainActor
final class WarnBeforeQuitManager {

    // MARK: - Properties

    @UserDefaultsWrapper(key: .warnBeforeQuitting, defaultValue: true)
    private var warnBeforeQuitting: Bool

    private var holdStartTime: Date?
    private var progressTimer: Timer?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var hasReleasedKeyAfterShowing = false

    /// Time required to hold CMD+Q to quit the app (in seconds)
    private let requiredHoldDuration: TimeInterval = 0.42
    /// Quick tap threshold - if released within this time, quit immediately
    private let quickTapThreshold: TimeInterval = 0.15
    /// Progress update interval for smooth animation
    private let progressUpdateInterval: TimeInterval = 0.016 // ~60fps
    
    // State machine for OverlayPresenter
    private let stateSubject: AsyncStream<QuitConfirmationState>.Continuation
    private let stateStreamStorage: AsyncStream<QuitConfirmationState>
    
    var stateStream: AsyncStream<QuitConfirmationState> {
        stateStreamStorage
    }
    
    private var currentState: QuitConfirmationState = .idle {
        didSet {
            stateSubject.yield(currentState)
        }
    }

    // MARK: - Initialization

    init() {
        // Create AsyncStream
        var continuation: AsyncStream<QuitConfirmationState>.Continuation!
        let stream = AsyncStream<QuitConfirmationState> { continuation = $0 }
        self.stateSubject = continuation
        self.stateStreamStorage = stream
    }

    deinit {
        stateSubject.finish()
        
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Public Interface

    /// Returns true if the warning feature is enabled
    var isEnabled: Bool {
        warnBeforeQuitting
    }

    /// Handles the quit action. Returns true if the quit should proceed immediately.
    func handleQuitRequest() -> Bool {
        guard warnBeforeQuitting else {
            return true
        }

        switch currentState {
        case .idle:
            currentState = .active
            hasReleasedKeyAfterShowing = false
            installKeyMonitor()
            return false
            
        case .active:
            if hasReleasedKeyAfterShowing {
                startHoldTimer()
            }
            return false
            
        case .holding, .completed:
            return false
        }
    }

    /// Disables the warning and allows immediate quit
    func disableWarning() {
        warnBeforeQuitting = false
        currentState = .completed(shouldQuit: true)
    }
    
    func reset() {
        guard case .completed = currentState else { return }
        currentState = .idle
    }

    // MARK: - Private

    private func startHoldTimer() {
        let targetTime = CACurrentMediaTime() + requiredHoldDuration
        currentState = .holding(targetTime: targetTime)
        
        holdStartTime = Date()

        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: progressUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    private func stopHoldTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        holdStartTime = nil
    }

    private func updateProgress() {
        guard let holdStartTime else { return }

        let elapsed = Date().timeIntervalSince(holdStartTime)
        let progress = CGFloat(elapsed / requiredHoldDuration)

        if progress >= 1.0 {
            performQuit()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            return event
        }

        // Monitor for clicks outside the overlay to dismiss it
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseEvent(event)
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        // Click outside dismisses overlay
        currentState = .completed(shouldQuit: false)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Check if Escape is pressed - dismiss the overlay
        if event.type == .keyDown && event.keyCode == 53 { // Escape key
            currentState = .completed(shouldQuit: false)
            return
        }

        // Check if CMD+Q is pressed while overlay is visible
        if event.type == .keyDown && event.keyCode == 12 && event.modifierFlags.contains(.command) {
            // Only start timer if user has released the key after showing overlay
            if hasReleasedKeyAfterShowing && holdStartTime == nil {
                startHoldTimer()
            }
            return
        }

        // Check if CMD key was released
        if event.type == .flagsChanged && !event.modifierFlags.contains(.command) {
            handleKeyRelease()
            return
        }

        // Check if Q key was released
        if event.type == .keyUp && event.keyCode == 12 { // Q key
            handleKeyRelease()
        }
    }

    private func handleKeyRelease() {
        // Only check for quick tap if we were tracking a hold (second press)
        // hasReleasedKeyAfterShowing being true means this is definitely a second press
        if hasReleasedKeyAfterShowing, let startTime = holdStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed <= quickTapThreshold {
                // Quick tap - quit immediately
                performQuit()
                return
            }
        }

        // Mark that user has released after overlay was shown
        hasReleasedKeyAfterShowing = true
        // Stop timer if running
        stopHoldTimer()
    }

    private func performQuit() {
        currentState = .completed(shouldQuit: true)
    }
}
