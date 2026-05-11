//
//  AddressBarPerfCoordinator.swift
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
/// All public methods are expected on the main thread.
final class AddressBarPerfCoordinator {

    typealias PixelFirer = (AddressBarPerfPixel) -> Void

    /// Default delay between terminator and pixel emission. Avoids competing with the
    /// post-navigation CPU window we're trying to keep clean for the SLO measurement itself.
    static let defaultDeferredEmitDelay: TimeInterval = 1.0

    private let recorder: AddressBarPerfRecorder
    private let deferredEmitDelay: TimeInterval
    private let pixelFirer: PixelFirer

    private var paintHook: AddressBarPerfPaintHook?
    private var pendingCharStartTime: TimeInterval?
    private var charNeedsRender = false
    private var suggestNeedsRender = false
    private var pendingEmit: DispatchWorkItem?

    init(
        recorder: AddressBarPerfRecorder = AddressBarPerfRecorder(),
        deferredEmitDelay: TimeInterval = AddressBarPerfCoordinator.defaultDeferredEmitDelay,
        pixelFirer: @escaping PixelFirer = { pixel in
            PixelKit.fire(pixel, frequency: .standard, includeAppVersionParameter: true)
        }
    ) {
        self.recorder = recorder
        self.deferredEmitDelay = deferredEmitDelay
        self.pixelFirer = pixelFirer
    }

    deinit {
        pendingEmit?.cancel()
    }

    // MARK: - Lifecycle

    /// Binds the coordinator's paint hook to `window` and starts ticking. Call when the address
    /// bar's window becomes available.
    func attach(to window: NSWindow) {
        paintHook?.stop()
        paintHook = AddressBarPerfPaintHook(window: window) { [weak self] outputTime in
            self?.handlePaint(at: outputTime)
        }
        paintHook?.start()
    }

    /// Stops and discards the paint hook. Call when the address bar's window is no longer available.
    func detach() {
        paintHook?.stop()
        paintHook = nil
    }

    // MARK: - Event signals

    /// Resets pending state for a new interaction. Call on focus-gained.
    func resetForNewInteraction() {
        cancelPendingEmit()
        recorder.reset()
        pendingCharStartTime = nil
        charNeedsRender = false
        suggestNeedsRender = false
    }

    /// Records a user-driven keystroke. Stamps the suggest stage's anchor immediately so a
    /// suggestions update that arrives before the buffer commit still finds it, and stashes
    /// the same t₀ for the char stage to consume at commit time.
    func markKeystroke() {
        pendingCharStartTime = recorder.markKeystrokeForSuggest()
    }

    /// Confirms that the buffer actually changed for a previously-marked keystroke. Pushes its
    /// t₀ into the char pending list and arms the next-paint flag. No-op when the buffer
    /// changed without a preceding `markKeystroke()` (programmatic edits) or after a previous
    /// suppressed keystroke whose slot was overwritten — those produce no char sample.
    func armCharRenderIfPending() {
        guard let t = pendingCharStartTime else { return }
        pendingCharStartTime = nil
        recorder.appendCharStartTime(at: t)
        charNeedsRender = true
    }

    /// Arms the suggest-render path. Call when the suggestions model emits an update.
    func markSuggestionsUpdated() {
        suggestNeedsRender = true
    }

    /// Snapshots the buffers synchronously and schedules a deferred pixel emission.
    /// Call on each interaction terminator (focus loss, navigation commit, AI-mode toggle,
    /// tab switch, window deactivate, app deactivate).
    func terminateInteraction() {
        let snapshot = recorder.takeAndClear()
        pendingCharStartTime = nil
        charNeedsRender = false
        suggestNeedsRender = false
        scheduleEmit(snapshot)
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
        cancelPendingEmit()

        let charBP = AddressBarPerfBucketing.basisPoints(for: snapshot.char)
        let suggestBP = AddressBarPerfBucketing.basisPoints(for: snapshot.suggest)
        let stages: AddressBarPerfPixel.Stages
        if !snapshot.char.isEmpty && !snapshot.suggest.isEmpty {
            stages = .both
        } else if !snapshot.char.isEmpty {
            stages = .charOnly
        } else {
            stages = .suggestOnly
        }
        let pixel = AddressBarPerfPixel(
            charBasisPoints: charBP,
            suggestBasisPoints: suggestBP,
            stages: stages
        )

        let firer = pixelFirer
        let work = DispatchWorkItem {
            firer(pixel)
        }
        pendingEmit = work
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + deferredEmitDelay, execute: work)
    }

    private func cancelPendingEmit() {
        pendingEmit?.cancel()
        pendingEmit = nil
    }
}
