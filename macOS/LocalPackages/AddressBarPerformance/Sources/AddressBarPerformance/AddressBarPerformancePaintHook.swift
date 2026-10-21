//
//  AddressBarPerformancePaintHook.swift
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
import CoreVideo
import Darwin

/// A `CVDisplayLink`-based per-frame callback bound to an `NSWindow`'s current display.
///
/// The hook fires its callback on the main thread once per display refresh while running.
/// The callback receives the upcoming frame's output time as `TimeInterval` (host-clock
/// seconds, directly comparable to `CACurrentMediaTime()`).
///
/// The hook recreates its underlying display link when the window moves to a different screen,
/// so a single instance keeps measuring correctly across multi-display setups.
@MainActor
final class AddressBarPerformancePaintHook {

    /// Receives the upcoming frame's output time, in `CACurrentMediaTime`-equivalent seconds.
    /// `@MainActor` to carry isolation through to the coordinator's `handlePaint(at:)`.
    typealias Callback = @MainActor (TimeInterval) -> Void

    private weak var window: NSWindow?
    private let onTick: Callback
    private var displayLink: CVDisplayLink?
    private var screenChangeObserver: NSObjectProtocol?

    /// Creates a hook bound to `window`. Does not start automatically; call `start()` when ready.
    init(window: NSWindow, onTick: @escaping Callback) {
        self.window = window
        self.onTick = onTick
        rebindToCurrentScreen()
        observeScreenChanges()
    }

    deinit {
        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts the display link. Idempotent.
    func start() {
        guard let link = displayLink, !CVDisplayLinkIsRunning(link) else { return }
        CVDisplayLinkStart(link)
    }

    /// Stops the display link. Idempotent.
    func stop() {
        guard let link = displayLink, CVDisplayLinkIsRunning(link) else { return }
        CVDisplayLinkStop(link)
    }

    /// `true` while the display link is firing callbacks.
    var isRunning: Bool {
        guard let link = displayLink else { return false }
        return CVDisplayLinkIsRunning(link)
    }

    // MARK: - Internals

    private func rebindToCurrentScreen() {
        let wasRunning = isRunning

        if let oldLink = displayLink, CVDisplayLinkIsRunning(oldLink) {
            CVDisplayLinkStop(oldLink)
        }
        displayLink = nil

        let displayID = currentDisplayID()
        var newLink: CVDisplayLink?
        let result = CVDisplayLinkCreateWithCGDisplay(displayID, &newLink)
        guard result == kCVReturnSuccess, let link = newLink else {
            assertionFailure("CVDisplayLinkCreateWithCGDisplay failed (display \(displayID), result \(result))")
            return
        }

        let setHandlerResult = CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, outputTimePtr, _, _ in
            guard self != nil else { return kCVReturnSuccess }
            let outputSeconds = Self.hostTimeToSeconds(outputTimePtr.pointee.hostTime)
            Task { @MainActor [weak self] in
                self?.onTick(outputSeconds)
            }
            return kCVReturnSuccess
        }
        guard setHandlerResult == kCVReturnSuccess else {
            assertionFailure("CVDisplayLinkSetOutputHandler failed with result \(setHandlerResult)")
            return
        }

        displayLink = link
        if wasRunning {
            CVDisplayLinkStart(link)
        }
    }

    private func observeScreenChanges() {
        guard let window else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebindToCurrentScreen()
            }
        }
    }

    private func currentDisplayID() -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let id = window?.screen?.deviceDescription[key] as? CGDirectDisplayID {
            return id
        }
        return CGMainDisplayID()
    }

    /// Pre-baked `hostTime → seconds` multiplier. `mach_timebase_info` is constant per boot,
    /// so we fetch it once and fold the nanosecond conversion in.
    nonisolated private static let hostTicksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// Converts a `CVTimeStamp.hostTime` (mach_absolute_time units) to seconds in the host clock.
    /// Values are directly comparable to `CACurrentMediaTime()`.
    nonisolated static func hostTimeToSeconds(_ hostTime: UInt64) -> TimeInterval {
        Double(hostTime) * hostTicksToSeconds
    }
}
