//
//  AddressBarPerformanceCoordinator.swift
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
import Foundation
import PixelKit

/// Owns the per-address-bar performance recorder, paint hook, and per-stage flags.
///
/// Callers signal events (keystroke, suggestions update, terminator) and the coordinator
/// handles the rest: pairing keystrokes with paints, clamping outliers, snapshotting buffers
/// at terminators, and scheduling the deferred pixel emission.
///
/// The paint hook is bound at `attach(to:)` but only ticks while there's an active interaction:
/// it starts on focus-gained, and a terminator schedules a deferred stop after `hookStopDelay`.
/// A re-focus or new keystroke within the linger cancels the stop, so Cmd-Tab cycles don't lose
/// measurements. A static `currentActive` enforces that at most one coordinator's hook ticks
/// across the app — a new activation displaces any other active coordinator immediately.
@MainActor
public final class AddressBarPerformanceCoordinator {

    /// Default delay between terminator and pixel emission. Avoids competing with the
    /// post-navigation CPU window we're trying to keep clean for the SLO measurement itself.
    static let defaultDeferredEmitDelay: TimeInterval = 1.0

    /// Default linger between terminator and paint-hook stop. Sized to absorb typical
    /// Cmd-Tab cycles and brief sheet dismissals so a quick return cancels the stop.
    static let defaultHookStopDelay: TimeInterval = 10.0

    /// At most one coordinator's paint hook ticks at a time across the app. Activating a
    /// new coordinator immediately stops any previously-active one (skipping its linger).
    static weak var currentActive: AddressBarPerformanceCoordinator?

    private let recorder: AddressBarPerformanceRecorder
    private let deferredEmitDelay: TimeInterval
    private let hookStopDelay: TimeInterval
    private let pixelFiring: PixelFiring?

    private var paintHook: AddressBarPerformancePaintHook?
    private var pendingCharStartTime: TimeInterval?
    private var charNeedsRender = false
    private var suggestNeedsRender = false
    var pendingHookStopTask: Task<Void, Never>?

    public convenience init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.init(
            recorder: AddressBarPerformanceRecorder(),
            deferredEmitDelay: AddressBarPerformanceCoordinator.defaultDeferredEmitDelay,
            hookStopDelay: AddressBarPerformanceCoordinator.defaultHookStopDelay,
            pixelFiring: pixelFiring
        )
    }

    init(
        recorder: AddressBarPerformanceRecorder,
        deferredEmitDelay: TimeInterval,
        hookStopDelay: TimeInterval,
        pixelFiring: PixelFiring?
    ) {
        self.recorder = recorder
        self.deferredEmitDelay = deferredEmitDelay
        self.hookStopDelay = hookStopDelay
        self.pixelFiring = pixelFiring
    }

    deinit {
        pendingHookStopTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Binds the coordinator's paint hook to `window`. The hook is not started here; it begins
    /// ticking on the next `resetForNewInteraction()` (focus-gained).
    public func attach(to window: NSWindow) {
        paintHook?.stop()
        paintHook = AddressBarPerformancePaintHook(window: window) { [weak self] outputTime in
            self?.handlePaint(at: outputTime)
        }
    }

    /// Stops and discards the paint hook. Call when the address bar's window is no longer available.
    public func detach() {
        cancelPendingHookStop()
        paintHook?.stop()
        paintHook = nil
        if AddressBarPerformanceCoordinator.currentActive === self {
            AddressBarPerformanceCoordinator.currentActive = nil
        }
    }

    // MARK: - Event signals

    /// Resets pending state for a new interaction. Call on focus-gained.
    public func resetForNewInteraction() {
        if let other = AddressBarPerformanceCoordinator.currentActive, other !== self {
            other.forceStopHookImmediately()
        }
        AddressBarPerformanceCoordinator.currentActive = self
        cancelPendingHookStop()
        recorder.reset()
        pendingCharStartTime = nil
        charNeedsRender = false
        suggestNeedsRender = false
        paintHook?.start()
    }

    /// Records a user-driven keystroke. Stamps the suggest stage's anchor immediately so a
    /// suggestions update that arrives before the buffer commit still finds it, and stashes
    /// the same t₀ for the char stage to consume at commit time. Also cancels any pending
    /// hook stop — a Cmd-Tab cycle that returns to typing without re-acquiring first responder
    /// still keeps the hook alive.
    ///
    /// For a physical keyDown, anchors t₀ to the event's `NSEvent.timestamp` — earlier than this
    /// call, same timebase as the paint hook. Other sources (paste, IME, dictation, programmatic)
    /// have no reliable originating event, so the recorder stamps its own clock.
    public func markKeystroke() {
        cancelPendingHookStop()
        var keystrokeTime: TimeInterval?
        // Optional-chain `NSApp?`, don't force-unwrap: `NSApp` is an IUO that is nil when no
        // `NSApplication` has been created, e.g. under unit tests — `NSApp.currentEvent` would
        // trap on every test run.
        if let event = NSApp?.currentEvent, event.type == .keyDown {
            keystrokeTime = event.timestamp
        }
        pendingCharStartTime = recorder.markKeystrokeForSuggest(at: keystrokeTime)
    }

    /// Confirms that the buffer actually changed for a previously-marked keystroke. Pushes its
    /// t₀ into the char pending list and arms the next-paint flag. No-op when the buffer
    /// changed without a preceding `markKeystroke()` (programmatic edits) or after a previous
    /// suppressed keystroke whose slot was overwritten — those produce no char sample.
    public func armCharRenderIfPending() {
        guard let t = pendingCharStartTime else { return }
        pendingCharStartTime = nil
        recorder.appendCharStartTime(at: t)
        charNeedsRender = true
    }

    /// Arms the suggest-render path. Call when the suggestions model emits an update.
    public func markSuggestionsUpdated() {
        suggestNeedsRender = true
    }

    /// Snapshots the buffers synchronously and schedules a deferred pixel emission.
    /// Call on each interaction terminator (focus loss, navigation commit, AI-mode toggle,
    /// tab switch, window deactivate, app deactivate). Also schedules a deferred paint-hook
    /// stop — re-focus or a new keystroke within `hookStopDelay` cancels it.
    public func terminateInteraction() {
        let snapshot = recorder.takeAndClear()
        pendingCharStartTime = nil
        charNeedsRender = false
        suggestNeedsRender = false
        scheduleEmit(snapshot)
        scheduleHookStop()
    }

    // MARK: - Internals

    /// Called by the paint hook on each display refresh. Internal access for testing.
    func handlePaint(at outputTime: TimeInterval) {
        if charNeedsRender {
            recorder.onCharRendered(at: outputTime)
            charNeedsRender = false
        }
        if suggestNeedsRender {
            recorder.onSuggestionsRendered(at: outputTime)
            suggestNeedsRender = false
        }
    }

    private func scheduleEmit(_ snapshot: (char: [Int], suggest: [Int])) {
        guard !snapshot.char.isEmpty || !snapshot.suggest.isEmpty else { return }

        let charBP = AddressBarPerformanceBucketing.basisPoints(for: snapshot.char)
        let suggestBP = AddressBarPerformanceBucketing.basisPoints(for: snapshot.suggest)
        let stages: AddressBarPerformancePixel.Stages
        if !snapshot.char.isEmpty && !snapshot.suggest.isEmpty {
            stages = .both
        } else if !snapshot.char.isEmpty {
            stages = .character
        } else {
            stages = .suggestion
        }
        let pixel = AddressBarPerformancePixel(
            charBasisPoints: charBP,
            suggestBasisPoints: suggestBP,
            stages: stages
        )

        let firing = pixelFiring
        let work = DispatchWorkItem {
            firing?.fire(pixel, frequency: .standard, includeAppVersionParameter: true)
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + deferredEmitDelay, execute: work)
    }

    private func scheduleHookStop() {
        cancelPendingHookStop()
        let delayInNanoseconds = UInt64(hookStopDelay * Double(NSEC_PER_SEC))
        pendingHookStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayInNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.paintHook?.stop()
            self.pendingHookStopTask = nil
            if AddressBarPerformanceCoordinator.currentActive === self {
                AddressBarPerformanceCoordinator.currentActive = nil
            }
        }
    }

    private func cancelPendingHookStop() {
        pendingHookStopTask?.cancel()
        pendingHookStopTask = nil
    }

    /// Immediate hook stop bypassing the linger — used when another coordinator displaces this one.
    private func forceStopHookImmediately() {
        cancelPendingHookStop()
        paintHook?.stop()
        if AddressBarPerformanceCoordinator.currentActive === self {
            AddressBarPerformanceCoordinator.currentActive = nil
        }
    }
}
