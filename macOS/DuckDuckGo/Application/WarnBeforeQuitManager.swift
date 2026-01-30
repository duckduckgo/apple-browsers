//
//  WarnBeforeQuitManager.swift
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
import Combine
import Common
import OSLog
import PixelKit
import SwiftUI
import QuartzCore

/// Manages the "Warn Before Quitting" feature that prevents accidental app termination.
///
/// Business logic layer that emits state changes via AsyncStream.
/// UI layer (WarnBeforeQuitOverlayPresenter) observes and reacts to state changes.
@MainActor
final class WarnBeforeQuitManager: ApplicationTerminationDecider {

    enum Constants {
        /// Time required to hold the quit shortcut to quit the app (in seconds)
        static let requiredHoldDuration: TimeInterval = 0.6

        /// Additional buffer time to allow progress animation to complete (in seconds)
        static let animationBufferDuration: TimeInterval = 0.1

        /// Time to wait after release for another quit shortcut press (in seconds)
        static let hideawayDuration: TimeInterval = 4.0

        /// Threshold before progress bar starts filling (prevents immediate visual feedback on quick press)
        static let progressThreshold: TimeInterval = 0.1

        /// Buffer time for detecting quick tap on second press (accounts for animation startup delay)
        static let quickTapDetectionBuffer: TimeInterval = 0.05

        /// Default delay to wait for UI animation to complete before proceeding with quit
        static let defaultAnimationDelay: TimeInterval = 0.3
    }

    /// The keyboard shortcut to monitor for confirmation (⌘Q, ⌘W…)
    private let shortcutKeyEquivalent: NSEvent.KeyEquivalent

    /// The action being confirmed (quit app or close pinned tabs)
    let action: ConfirmationAction

    /// Pixel firing for analytics
    private let pixelFiring: PixelFiring?

    /// Provides current time (injectable for testing)
    private let now: () -> Date

    /// Receives events from the event loop (injectable for testing)
    private let eventReceiver: (NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent?

    /// Creates timers (injectable for testing)
    private let timerFactory: (TimeInterval, @escaping @MainActor () -> Void) -> Timer

    /// Delay to wait for UI animation to complete before proceeding with quit (injectable for testing)
    private let animationDelay: TimeInterval

    /// Checks if modifiers are currently held (injectable for testing)
    private let isModifierHeld: (NSEvent.ModifierFlags) -> Bool

    // State machine

    enum State: Equatable {
        case idle
        case keyDown  // Key pressed, waiting to confirm it's a hold (before progressThreshold)
        case holding(startTime: TimeInterval, targetTime: TimeInterval)  // Confirmed hold, progress animating
        case waitingForSecondPress
        case completed(shouldProceed: Bool)
    }

    private var currentState: State = .idle {
        didSet {
            Logger.general.debug("WarnBeforeQuitManager: State changed to \(String(describing: self.currentState))")
            stateSubject.yield(currentState)
        }
    }

    private let stateSubject: AsyncStream<State>.Continuation
    private let stateStreamStorage: AsyncStream<State>
    nonisolated var stateStream: AsyncStream<State> {
        stateStreamStorage
    }

    // Callback to check if the warning is enabled
    private let isWarningEnabled: () -> Bool

    // Callback when hover state changes - restarts timer with appropriate duration
    private var onHoverChange: ((Bool) -> Void)?
    // If mouse is hovering over the overlay on show
    private var isHovering = false
    // Track whether the shortcut key is still being held (to wait for release in delegate callback)
    private var isShortcutKeyHeld = false

    private let interceptorToken = UUID()

    // MARK: - Initialization

    init?(currentEvent: NSEvent,
          action: ConfirmationAction,
          isWarningEnabled: @escaping () -> Bool,
          pixelFiring: PixelFiring? = PixelKit.shared,
          now: @escaping () -> Date = Date.init,
          eventReceiver: ((NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent?)? = nil,
          timerFactory: ((TimeInterval, @escaping @MainActor () -> Void) -> Timer)? = nil,
          animationDelay: TimeInterval = Constants.defaultAnimationDelay,
          isModifierHeld: ((NSEvent.ModifierFlags) -> Bool)? = nil) {
        // Validate this is a keyDown event with modifier and valid character
        guard currentEvent.type == .keyDown,
              let keyEquivalent = currentEvent.keyEquivalent, !keyEquivalent.modifierMask.isEmpty else { return nil }
        Logger.general.debug("WarnBeforeQuitManager.init currentEvent: \(currentEvent)")
        self.shortcutKeyEquivalent = keyEquivalent
        self.action = action
        self.pixelFiring = pixelFiring
        self.isWarningEnabled = isWarningEnabled
        self.now = now
        self.eventReceiver = eventReceiver ?? MainActor.assumeMainThread { NSApp.nextEvent }
        self.timerFactory = timerFactory ?? { @MainActor interval, block in
            dispatchPrecondition(condition: .onQueue(.main))
            let timer = Timer(timeInterval: interval, repeats: false) { _ in MainActor.assumeMainThread(block) }
            RunLoop.current.add(timer, forMode: .common)
            return timer
        }
        self.animationDelay = animationDelay
        self.isModifierHeld = isModifierHeld ?? { requiredModifiers in
            let currentModifiers = NSEvent.modifierFlags.deviceIndependent
            return currentModifiers.intersection(requiredModifiers) == requiredModifiers
        }
        // Create state AsyncStream for external observation
        (stateStreamStorage, stateSubject) = AsyncStream<State>.makeStream(of: State.self, bufferingPolicy: .bufferingNewest(3))
    }

    deinit {
        stateSubject.finish()
        DispatchQueue.main.async { [interceptorToken] in
            (NSApp as? Application)?.resetEventInterceptor(token: interceptorToken)
        }
    }

    // MARK: - Public

    /// Called when mouse hover state changes over the overlay
    /// - Parameter isHovering: true if mouse entered, false if exited
    func setMouseHovering(_ isHovering: Bool) {
        Logger.general.debug("WarnBeforeQuitManager: setMouseHovering(\(isHovering))")
        onHoverChange?(isHovering) ?? { self.isHovering = isHovering }()
    }

    // MARK: - ApplicationTerminationDecider

    func shouldTerminate(isAsync: Bool) -> TerminationQuery {
        dispatchPrecondition(condition: .onQueue(.main))

        let warningEnabled = isWarningEnabled()
        Logger.general.debug("WarnBeforeQuitManager: shouldTerminate(isAsync: \(isAsync), enabled: \(warningEnabled))")

        // Don't show confirmation if another decider already delayed termination or feature is disabled
        guard !isAsync, warningEnabled, currentState == .idle else {
            assert(currentState == .idle, "shouldTerminate should only be called when currentState is .idle, but currentState is \(currentState)")
            return .sync(.next)
        }

        // Fire shown pixel (only for quit, not close tab)
        if action == .quit {
            pixelFiring?.fire(GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount)
        }

        // Show confirmation and wait synchronously for hold completion or release
        switch trackEventsForHoldingPhase() {
        case .completed(let shouldProceed) where action == .quit:
            // Fire pixel and wait for completion before terminating
            /* WHEN THE PIXEL IS REMOVED, REMOVE THIS CASE!
            */
            let task = Task<TerminationDecision, Never> {
                let pixel = shouldProceed ? GeneralPixel.warnBeforeQuitQuit : GeneralPixel.warnBeforeQuitCancelled
                await self.pixelFiring?.fireAndWait(pixel, frequency: .standard)

                self.currentState = .completed(shouldProceed: shouldProceed)
                return .next
            }
            if shouldProceed {
                // Install event interceptor to prevent beeps for repeated shortcut key events,
                // reset in the `deciderSequenceCompleted` delegate callback
                installEventInterceptor()
                return .async(task) // wait for the pixel request then quit
            } else {
                return .sync(.cancel) // return .sync, Task runs async
            }

        case .completed(let shouldProceed):
            if shouldProceed {
                // Install event interceptor to prevent beeps for repeated shortcut key events
                installEventInterceptor()
            }
            currentState = .completed(shouldProceed: shouldProceed)
            return .sync(shouldProceed ? .next : .cancel)

        case .releasedEarly:
            // First press released early - go to waiting for second press
            break
        }

        // Shortcut released early - wait for second press asynchronously
        Logger.general.debug("WarnBeforeQuitManager: Key released early, entering async wait")
        return .async(Task {
            let shouldProceed = await waitForSecondPress()

            // Emit completed state - UI will hide overlay
            currentState = .completed(shouldProceed: shouldProceed)

            // Fire pixel based on result (only for quit, not close tab)
            if self.action == .quit {
                let pixel = shouldProceed ? GeneralPixel.warnBeforeQuitQuit : GeneralPixel.warnBeforeQuitCancelled
                await self.pixelFiring?.fireAndWait(pixel, frequency: .standard)
            }

            // Wait for a brief delay for animation to complete before quitting
            if shouldProceed && action == .quit && self.animationDelay > 0 {
                try? await Task.sleep(interval: self.animationDelay)
            }

            let decision: TerminationDecision = shouldProceed ? .next : .cancel
            Logger.general.debug("WarnBeforeQuitManager: Returning \(String(describing: decision))")
            return decision
        })
    }

    // MARK: - Private

    private enum HoldingPhaseResult {
        case completed(shouldProceed: Bool)
        case releasedEarly
    }

    /// Waits synchronously for user to either hold Cmd+[Q|W] long enough or release it early.
    /// - Returns: Result indicating completion or early release
    private func trackEventsForHoldingPhase() -> HoldingPhaseResult {
        dispatchPrecondition(condition: .onQueue(.main))

        let keyEquivalent = shortcutKeyEquivalent

        // Start in keyDown state - UI shows overlay but no progress yet
        currentState = .keyDown

        // Initial deadline: wait for progressThreshold to confirm it's a hold
        var deadline = now().advanced(by: Constants.progressThreshold)

        // Wait for either key release or hold duration completion
        while now() < deadline {
            // Check if warning was disabled during the loop
            guard isWarningEnabled() else {
                Logger.general.debug("WarnBeforeQuitManager: Warning disabled during hold, exiting loop")
                return .completed(shouldProceed: true)
            }

            guard let event = eventReceiver([.keyUp, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .flagsChanged], deadline, .eventTracking, true) else {
                // deadline reached
                if case .keyDown = currentState {
                    // Reached progressThreshold - transition to holding and start progress
                    Logger.general.debug("WarnBeforeQuitManager: progressThreshold reached, transitioning to holding for \(Constants.requiredHoldDuration)s")
                    let startTime = now().timeIntervalSinceReferenceDate
                    // Set targetTime with small buffer for smooth visual completion
                    currentState = .holding(startTime: startTime, targetTime: startTime + Constants.requiredHoldDuration + Constants.animationBufferDuration)
                    deadline = now().advanced(by: Constants.requiredHoldDuration)
                    continue

                } else {
                    // Reached full hold duration - hold completed
                    Logger.general.debug("WarnBeforeQuitManager: Hold completed by deadline")
                    // Mark that shortcut key is still held - will wait for release in delegate callback
                    isShortcutKeyHeld = true
                    return .completed(shouldProceed: true)
                }
            }

            switch event.type {
            case .flagsChanged where event.modifierFlags.deviceIndependent.intersection(keyEquivalent.modifierMask) != keyEquivalent.modifierMask:
                // Modifier key was released early
                Logger.general.debug("WarnBeforeQuitManager: Modifier released")
                return .releasedEarly

            case .keyDown where event.keyEquivalent == shortcutKeyEquivalent:
                Logger.general.debug("WarnBeforeQuitManager: consuming consequent keyDown for \(event)")
                continue

            case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
                // Other key pressed during hold - cancel and pass through
                var keyDescr: String { event.type == .keyDown ? "'\(event.keyEquivalent?.charCode ?? "")' key" : "button \(event.buttonNumber)" }
                Logger.general.debug("WarnBeforeQuitManager: \(keyDescr) pressed during hold, canceling")
                NSApp.postEvent(event, atStart: true)
                return .completed(shouldProceed: false)

            case .keyUp where event.charactersIgnoringModifiers == keyEquivalent.charCode:
                // Shortcut key was released early
                Logger.general.debug("WarnBeforeQuitManager: Key '\(keyEquivalent.charCode)' released")
                return .releasedEarly

            default:
                // Repost other events to keep app responsive
                NSApp.postEvent(event, atStart: true)
            }
        }

        // Loop ended, deadline reached - shouldn‘t reach here but handle gracefully
        return .completed(shouldProceed: true)
    }

    private func waitForSecondPress() async -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        // Emit waiting state - UI can show "press again" or start fadeout
        currentState = .waitingForSecondPress

        return await withCancellableContinuation { [shortcutKeyEquivalent] resumeContinuation, wasResumed in
            var timer: Timer?

            @MainActor
            func resume(with shouldProceedDecision: Bool) {
                timer?.invalidate()
                timer = nil
                onHoverChange = nil

                // Check if already resumed
                guard !wasResumed() else { return }

                // If warning was just disabled (e.g., by clicking "Don't Ask Again"), allow action to proceed
                let shouldProceed = shouldProceedDecision || !isWarningEnabled()
                Logger.general.debug("WarnBeforeQuitManager: Resuming with shouldProceed=\(shouldProceed)\(!shouldProceedDecision && shouldProceed ? " (warning disabled)" : "")")

                // If proceeding: install beep-prevention interceptor that consumes repeated keyDown events
                // (user may still be holding the key, which would cause system beeps if not consumed)
                if shouldProceed {
                    self.installEventInterceptor()
                } else {
                    (NSApp as? Application)?.resetEventInterceptor(token: interceptorToken)
                }

                // Resume continuation (this must be last)
                resumeContinuation(shouldProceed)
            }

            @MainActor
            func startTimer() {
                timer?.invalidate()
                let duration = Constants.hideawayDuration
                Logger.general.debug("WarnBeforeQuitManager: Timer started (\(duration)s)")
                timer = timerFactory(duration) {
                    Logger.general.debug("WarnBeforeQuitManager: Timer expired")
                    resume(with: false)
                }
            }

            @MainActor
            func setupHoverCallback() {
                self.onHoverChange = { isHovering in
                    if isHovering {
                        Logger.general.debug("WarnBeforeQuitManager: Hover detected, stopping timer")
                        timer?.invalidate()
                        timer = nil
                    } else {
                        Logger.general.debug("WarnBeforeQuitManager: Hover ended, restarting timer")
                        startTimer()
                    }
                }
            }

            // Set callback for mouse hover state change - stops timer while hovering, restarts when exiting
            setupHoverCallback()

            // Install event interceptor hook for the shortcut, Escape, and clicks
            // Don't overwrite existing interceptor - if one exists, cancel this manager
            guard (NSApp as? Application)?.eventInterceptorToken ?? interceptorToken == interceptorToken else {
                Logger.general.error("WarnBeforeQuitManager: Another event interceptor already active, cancelling")
                resume(with: false)
                return
            }
            (NSApp as? Application)?.installEventInterceptor(token: interceptorToken) { event in
                switch event.type {
                case .keyDown where event.keyEquivalent == .escape:
                    Logger.general.debug("WarnBeforeQuitManager: Escape pressed")
                    resume(with: false)
                    return nil // Consume event

                case .keyDown where event.keyEquivalent == shortcutKeyEquivalent:
                    Logger.general.debug("WarnBeforeQuitManager: ⌘'\(shortcutKeyEquivalent.charCode)' pressed again")

                    // Clean up timer and hover callback before entering hold phase
                    timer?.invalidate()
                    timer = nil
                    self.onHoverChange = nil

                    // Record time when second press started (for determining quick tap vs hold)
                    let secondPressStartTime = self.now()

                    // Handle second press with same hold detection as first press
                    let result = self.trackEventsForHoldingPhase()

                    switch result {
                    case .completed(let shouldProceed):
                        if shouldProceed {
                            // Held through duration - proceed
                            Logger.general.debug("WarnBeforeQuitManager: Second press held through duration, proceeding")
                            self.isShortcutKeyHeld = true
                        } else {
                            // Cancelled by other key press
                            Logger.general.debug("WarnBeforeQuitManager: Second press cancelled")
                        }
                        resume(with: shouldProceed)

                    case .releasedEarly:
                        // Check if released before progress visible (quick tap) or after (return to waiting)
                        let elapsedTime = self.now().timeIntervalSince(secondPressStartTime)
                        // Reset progress in case it‘s started animating before the key release
                        self.currentState = .waitingForSecondPress
                        // Add buffer to account for animation startup time
                        if elapsedTime < Constants.progressThreshold + Constants.quickTapDetectionBuffer {
                            // Quick tap - confirm immediately
                            Logger.general.debug("WarnBeforeQuitManager: Second press released in \(elapsedTime)s, confirming")
                            resume(with: true)
                        } else {
                            // Released after progress started - return to waiting
                            Logger.general.debug("WarnBeforeQuitManager: Second press released after \(elapsedTime)s, returning to wait")
                            // Restore hover callback (was cleared at line 390 before entering hold phase)
                            setupHoverCallback()
                            // Only start timer if not already hovering
                            if !self.isHovering {
                                startTimer()
                            }
                        }
                    }

                    return nil // Consume event

                case .keyDown:
                    Logger.general.debug("WarnBeforeQuitManager: '\(event.keyEquivalent?.charCode ?? "")' key pressed, canceling")
                    resume(with: false)
                    return event // Pass through for normal function

                case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                    Logger.general.debug("WarnBeforeQuitManager: \(event.type == .leftMouseDown ? "Left" : event.type == .rightMouseDown ? "Right" : "Other") mouse down")
                    // Give it some time for the click to be processed first (e.g., "Don't Ask Again" button click)
                    // The resume function will check if warning was disabled and adjust accordingly
                    DispatchQueue.main.async {
                        resume(with: false)
                    }
                    return event // Let click be processed by the system

                default:
                    return event // Pass through all other events
                }
            }

            // Start hideaway timer unless mouse is already hovering
            // (onHoverChange only fires on state changes, not initial state)
            if !isHovering {
                startTimer()
            } else {
                Logger.general.debug("WarnBeforeQuitManager: Mouse already hovering, not starting timer")
            }
        } onCancel: {
            Logger.general.debug("WarnBeforeQuitManager: Task cancelled, triggering cleanup")
            return false
        }
    }

    func deciderSequenceCompleted(shouldProceed: Bool) {
        Logger.general.debug("WarnBeforeQuitManager: deciderSequenceCompleted(shouldProceed: \(shouldProceed))")

        // Wait for shortcut key release if it was still held when decision was made
        if shouldProceed && isShortcutKeyHeld {
            waitForKeyRelease(keyEquivalent: shortcutKeyEquivalent)
            isShortcutKeyHeld = false
        }
        // Reset event interceptor set to prevent beeps for repeated shortcut key events
        // Done on the next pass to let the event loop process any queued repeated key events before resetting the interceptor
        DispatchQueue.main.async { [interceptorToken] in
            (NSApp as? Application)?.resetEventInterceptor(token: interceptorToken)
        }
    }

    /// Wait for the shortcut key to be released (to prevent sending it to the next active app)
    private func waitForKeyRelease(keyEquivalent: NSEvent.KeyEquivalent) {
        dispatchPrecondition(condition: .onQueue(.main))

        // Safety check: If the key is already released, don't wait
        guard isModifierHeld(keyEquivalent.modifierMask) else {
            Logger.general.debug("WarnBeforeQuitManager: Key already released, no need to wait")
            return
        }

        Logger.general.debug("WarnBeforeQuitManager: Waiting for key release...")

        // Set a sanity timeout to prevent indefinite waiting (e.g., if user keeps holding key for a long time)
        let timeout: TimeInterval = 3.0
        let deadline = now().addingTimeInterval(timeout)

        while true {
            // Wait for key up or flags changed events with timeout
            guard let event = eventReceiver([.keyDown, .keyUp, .flagsChanged], deadline, .eventTracking, true) else {
                // Timeout reached - stop waiting
                Logger.general.debug("WarnBeforeQuitManager: Key release wait timed out after \(timeout)s")
                return
            }

            switch event.type {
            case .keyUp where event.charactersIgnoringModifiers == keyEquivalent.charCode:
                Logger.general.debug("WarnBeforeQuitManager: Key released")
                return

            case .flagsChanged where event.modifierFlags.deviceIndependent.intersection(keyEquivalent.modifierMask) != keyEquivalent.modifierMask:
                Logger.general.debug("WarnBeforeQuitManager: Modifier released")
                return

            default:
                // Consume all other events to prevent them from reaching other apps
                continue
            }
        }
    }

    /// Install event interceptor to prevent beeps from repeated shortcut key presses
    private func installEventInterceptor() {
        // Don't overwrite existing interceptor
        guard (NSApp as? Application)?.eventInterceptorToken ?? interceptorToken == interceptorToken else { return }
        (NSApp as? Application)?.installEventInterceptor(token: interceptorToken) { [shortcutKeyEquivalent] event in
            if event.type == .keyDown && event.keyEquivalent == shortcutKeyEquivalent {
                return nil // consume event to prevent beep
            }
            return event // pass through other events
        }
    }

}

// MARK: - PixelFiring Async Extension

extension PixelFiring {
    /// Fire a pixel and wait for completion asynchronously (with timeout)
    func fireAndWait(_ event: PixelKitEvent, frequency: PixelKit.Frequency, timeout: TimeInterval = 1) async {
        try? await withTimeout(timeout) {
            await withCancellableContinuation { resume, _ in
                fire(event, frequency: frequency) { _, _ in
                    DispatchQueue.main.asyncOrNow {
                        resume(())
                    }
                }
            } onCancel: {
                // Timeout - continue with termination anyway
                Logger.general.error("WarnBeforeQuitManager: Pixel firing timed out")
            }
        }
    }
}

/// Helper to execute an async operation with continuation that supports cancellation and allows multiple resume attempts
/// - Parameter onCancel: The value to return when the task is cancelled
/// - Parameter operation: The operation to execute. Receives:
///   - resume: Callback to resume the continuation with a value
///   - wasResumed: Callback to check if continuation was already resumed (returns true if already resumed)
@MainActor
private func withCancellableContinuation<T>(
    _ operation: (/*resume:*/ @escaping @MainActor (T) -> Void, /*isResumed:*/ @escaping @MainActor () -> Bool) -> Void,
    onCancel cancellationValue: @escaping @MainActor () -> T
) async -> T {
    var isResumed = false
    var cancellationHandler: (() -> Void)?

    return await withTaskCancellationHandler { @MainActor in
        await withCheckedContinuation { @MainActor continuation in
            let checkIfResumed = { () -> Bool in
                return isResumed
            }

            let resume: @MainActor (T) -> Void = { (value: T) in
                guard !isResumed else { return }
                isResumed = true
                cancellationHandler = nil
                continuation.resume(returning: value)
            }

            // Store cancellation handler for when task is cancelled
            cancellationHandler = {
                resume(cancellationValue())
            }
            guard !Task.isCancelled else {
                resume(cancellationValue())
                return
            }

            operation(resume, checkIfResumed)
        }
    } onCancel: {
        DispatchQueue.main.asyncOrNow {
            cancellationHandler?()
        }
    }
}
