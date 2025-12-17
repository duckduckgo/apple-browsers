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
import Common
import OSLog
import SwiftUI
import QuartzCore

// MARK: - State Machine

enum QuitConfirmationState: Equatable {
    case idle
    case holding(startTime: TimeInterval, targetTime: TimeInterval)
    case waitingForSecondPress(hideUntil: TimeInterval)
    case completed(shouldQuit: Bool)
}

/// Manages the "Warn Before Quitting" feature that prevents accidental app termination.
///
/// Business logic layer that emits state changes via AsyncStream.
/// UI layer (OverlayPresenter) observes and reacts to state changes.
@MainActor
final class WarnBeforeQuitManager: ApplicationTerminationDecider {

    enum Constants {
        /// Time required to hold the quit shortcut to quit the app (in seconds)
        static let requiredHoldDuration: TimeInterval = 0.42

        /// Additional buffer time to allow progress animation to complete (in seconds)
        static let animationBufferDuration: TimeInterval = 0.1

        /// Time to wait after release for another quit shortcut press (in seconds)
        static let hideawayDuration: TimeInterval = 1.5

        /// Extended time to wait when mouse is hovering over the overlay (in seconds)
        static let extendedHideawayDuration: TimeInterval = 4.0
    }

    /// The keyboard shortcut to monitor for confirmation (⌘Q, ⌘W…)
    private let shortcutKeyEquivalent: NSEvent.KeyEquivalent

    /// Provides current time (injectable for testing)
    private let now: () -> Date

    /// Receives events from the event loop (injectable for testing)
    private let eventReceiver: (NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent?

    /// Creates timers (injectable for testing)
    private let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer

    // State machine
    private let stateSubject: AsyncStream<QuitConfirmationState>.Continuation
    private let stateStreamStorage: AsyncStream<QuitConfirmationState>

    // to be moved to settings
    @UserDefaultsWrapper(key: .warnBeforeQuitting, defaultValue: true)
    private var warnBeforeQuitting: Bool

    nonisolated var stateStream: AsyncStream<QuitConfirmationState> {
        stateStreamStorage
    }

    private var currentState: QuitConfirmationState = .idle {
        didSet {
            Logger.general.debug("WarnBeforeQuitManager: State changed to \(String(describing: self.currentState))")
            stateSubject.yield(currentState)
        }
    }

    // Callback to signal "Don't Ask Again" was clicked
    private var onDontAskAgain: (() -> Void)?

    // Callback when hover state changes - restarts timer with appropriate duration
    private var onHoverChange: ((Bool) -> Void)?
    // If mouse is hovering over the overlay on show
    private var isHovering = false

    // MARK: - Initialization

    init?(currentEvent: NSEvent,
          now: @escaping () -> Date = Date.init,
          eventReceiver: ((NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent?)? = nil,
          timerFactory: ((TimeInterval, @escaping () -> Void) -> Timer)? = nil) {
        // Validate this is a keyDown event with modifier and valid character
        guard currentEvent.type == .keyDown,
              let keyEquivalent = currentEvent.keyEquivalent, !keyEquivalent.modifierMask.isEmpty else { return nil }

        self.shortcutKeyEquivalent = keyEquivalent
        self.now = now
        self.eventReceiver = eventReceiver ?? MainActor.assumeMainThread { NSApp.nextEvent }
        self.timerFactory = timerFactory ?? { interval, block in
            let timer = Timer(timeInterval: interval, repeats: false) { _ in block() }
            RunLoop.current.add(timer, forMode: .common)
            return timer
        }
        // Create state AsyncStream for external observation
        (stateStreamStorage, stateSubject) = AsyncStream<QuitConfirmationState>.makeStream(of: QuitConfirmationState.self, bufferingPolicy: .bufferingNewest(3))
    }

    deinit {
        stateSubject.finish()
    }

    // MARK: - Public Interface

    /// Disables the warning and allows immediate quit
    func disableWarning() {
        Logger.general.debug("WarnBeforeQuitManager: disableWarning called")
        warnBeforeQuitting = false
        onDontAskAgain?()
    }

    /// Called when mouse hover state changes over the overlay
    /// - Parameter isHovering: true if mouse entered, false if exited
    func setMouseHovering(_ isHovering: Bool) {
        Logger.general.debug("WarnBeforeQuitManager: setMouseHovering(\(isHovering))")
        onHoverChange?(isHovering) ?? { self.isHovering = isHovering }()
    }

    // MARK: - ApplicationTerminationDecider

    func shouldTerminate(isAsync: Bool) -> TerminationQuery {
        let warnBeforeQuitting = warnBeforeQuitting
        Logger.general.debug("WarnBeforeQuitManager: shouldTerminate(isAsync: \(isAsync), enabled: \(warnBeforeQuitting))")

        // Don't show confirmation if another decider already delayed termination or feature is disabled
        guard !isAsync, warnBeforeQuitting, currentState == .idle else {
            assert(currentState == .idle, "shouldTerminate should only be called when currentState is .idle, but currentState is \(currentState)")
            return .sync(.next)
        }

        // Show confirmation and wait for hold completion or release
        if trackEventsForHoldingPhase() {
            // Held long enough or "Don't Show Again" clicked
            return .sync(.next)
        }

        // Shortcut released early - wait for second press asynchronously
        Logger.general.debug("WarnBeforeQuitManager: Key released early, entering async wait")
        return .async(Task {
            let shouldQuit = await waitForSecondPress()

            // Emit completed state - UI will hide overlay
            currentState = .completed(shouldQuit: shouldQuit)

            let decision: TerminationDecision = shouldQuit ? .next : .cancel
            Logger.general.debug("WarnBeforeQuitManager: Returning \(String(describing: decision))")
            return decision
        })
    }

    // MARK: - Private

    /// Waits synchronously for user to either hold Cmd+[Q|W] long enough or release it early.
    /// - Returns: `true` if held long enough or "Don't Show Again" clicked, `false` if released early
    private func trackEventsForHoldingPhase() -> Bool {
        // Start hold timer - UI will show overlay with progress
        let startTime = now().timeIntervalSinceReferenceDate
        currentState = .holding(startTime: startTime, targetTime: startTime + Constants.requiredHoldDuration)
        let keyEquivalent = shortcutKeyEquivalent

        // Include buffer time to allow the progress animation to complete smoothly
        let deadline = now().advanced(by: Constants.requiredHoldDuration + Constants.animationBufferDuration)
        // Wait for either key release or hold duration completion
        while now() < deadline {
            // Check if warning was disabled during the loop
            guard warnBeforeQuitting else {
                Logger.general.debug("WarnBeforeQuitManager: Warning disabled during hold, exiting loop")
                currentState = .completed(shouldQuit: true)
                return true
            }

            guard let event = eventReceiver([.keyUp, .flagsChanged], deadline, .eventTracking, true) else {
                // If no event, we reached the deadline - hold completed
                Logger.general.debug("WarnBeforeQuitManager: Hold completed by deadline")
                currentState = .completed(shouldQuit: true)
                return true
            }

            switch event.type {
            case .flagsChanged where event.modifierFlags.deviceIndependent.intersection(keyEquivalent.modifierMask) != keyEquivalent.modifierMask:
                // Modifier key was released - need to wait for second press
                Logger.general.debug("WarnBeforeQuitManager: Modifier released")
                return false

            case .keyUp where event.charactersIgnoringModifiers == keyEquivalent.charCode:
                // Shortcut key was released - need to wait for second press
                Logger.general.debug("WarnBeforeQuitManager: Key '\(keyEquivalent.charCode)' released")
                return false

            default:
                // Repost other events to keep app responsive
                NSApp.postEvent(event, atStart: true)
            }
        }

        // Loop ended, deadline reached - hold completed
        currentState = .completed(shouldQuit: true)
        return true
    }

    private func waitForSecondPress() async -> Bool {
        // Emit waiting state - UI can show "press again" or start fadeout
        let hideUntil = now().timeIntervalSinceReferenceDate + Constants.hideawayDuration
        currentState = .waitingForSecondPress(hideUntil: hideUntil)

        final class CancellationState {
            var onCancel: (() -> Void)?
        }
        let cancellationState = CancellationState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { [shortcutKeyEquivalent] continuation in
                var eventMonitor: Any?
                var timer: Timer?
                var resumed = false

                func resume(with value: Bool) {
                    guard !resumed else { return }
                    resumed = true
                    Logger.general.debug("WarnBeforeQuitManager: Resuming with \(value)")

                    eventMonitor.map(NSEvent.removeMonitor)
                    timer?.invalidate()
                    cancellationState.onCancel = nil
                    MainActor.assumeMainThread {
                        onDontAskAgain = nil
                        onHoverChange = nil
                    }

                    continuation.resume(returning: value)
                }

                // Set up cancellation handler
                cancellationState.onCancel = {
                    Logger.general.debug("WarnBeforeQuitManager: Cancellation handler invoked, cleaning up")
                    resume(with: false)
                }

                @MainActor
                func startTimer(hovering: Bool) {
                    timer?.invalidate()
                    let duration = hovering ? Constants.extendedHideawayDuration : Constants.hideawayDuration
                    Logger.general.debug("WarnBeforeQuitManager: Timer started (\(duration)s\(hovering ? ", extended" : ""))")
                    timer = timerFactory(duration) {
                        Logger.general.debug("WarnBeforeQuitManager: Timer expired")
                        resume(with: false)
                    }
                }

                // Set callback for "Don't Ask Again" clicked during wait
                onDontAskAgain = {
                    Logger.general.debug("WarnBeforeQuitManager: Don't Ask Again clicked")
                    resume(with: true)
                }

                // Set callback for mouse hover state change - restarts timer with extended duration if hovering
                onHoverChange = { isHovering in
                    if isHovering {
                        Logger.general.debug("WarnBeforeQuitManager: Hover detected")
                        startTimer(hovering: isHovering)
                    }
                }

                // Install event monitor for the shortcut, Escape, and clicks
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
                    switch event.type {
                    case .keyDown where event.keyEquivalent == .escape:
                        Logger.general.debug("WarnBeforeQuitManager: Escape pressed")
                        resume(with: false)
                        return nil // Consume event

                    case .keyDown where event.keyEquivalent == shortcutKeyEquivalent:
                        Logger.general.debug("WarnBeforeQuitManager: ⌘'\(shortcutKeyEquivalent.charCode)' pressed again")
                        resume(with: true)
                        return nil // Consume event

                    case .leftMouseDown, .rightMouseDown:
                        Logger.general.debug("WarnBeforeQuitManager: \(event.type == .leftMouseDown ? "Left" : "Right") mouse down")
                        // Give it some time for the click to be processed first if it's a "Don't Ask Again" click (in `onDontAskAgain`),
                        // otherwise cancel the hold and quit the app
                        DispatchQueue.main.async {
                            resume(with: false)
                        }
                        return event // Let click be processed by the system

                    default:
                        assertionFailure("WarnBeforeQuitManager: Unexpected event type: \(event.type)")
                        return event
                    }
                }

                // Start hideaway timer
                startTimer(hovering: isHovering)
            }
        } onCancel: {
            Logger.general.debug("WarnBeforeQuitManager: Task cancelled, triggering cleanup")
            cancellationState.onCancel?()
        }
    }
}
