//
//  UsageContextProvider.swift
//  DuckDuckGo
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

import GameController
import UIKit

/// Coarse usage dimensions attached to Duck.ai pixels and wide events. Kept to closed, two-value enums.
struct UsageContext: Equatable {

    enum Layout: String, Codable {
        /// The tabs-bar layout iPads get at 678pt and wider.
        case regular
        /// The phone layout: every iPhone, and iPad windows narrower than 678pt.
        case compact
    }

    enum WindowMode: String, Codable {
        case fullScreen = "full_screen"
        /// Split View, Slide Over or a Stage Manager window narrower than the screen.
        case partial
    }

    let hardwareKeyboard: Bool
    let layout: Layout
}

protocol UsageContextProviding {
    /// Safe to read from any thread, so pixels fired off the main thread can carry it.
    var currentContext: UsageContext { get }
    @MainActor var currentWindowMode: UsageContext.WindowMode { get }
}

struct UsageContextProvider: UsageContextProviding {

    private let isPad: Bool
    private let isHardwareKeyboardConnected: () -> Bool
    private let isLargeWidth: () -> Bool
    private let windowAndScreenWidths: @MainActor () -> (window: CGFloat, screen: CGFloat)?

    init(isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad,
         keyboardMonitor: HardwareKeyboardMonitor = AppDependencyProvider.shared.hardwareKeyboardMonitor,
         isLargeWidth: @escaping () -> Bool = { AppWidthObserver.shared.isLargeWidth },
         windowAndScreenWidths: @escaping @MainActor () -> (window: CGFloat, screen: CGFloat)? = Self.keyWindowWidths) {
        self.isPad = isPad
        self.isHardwareKeyboardConnected = { keyboardMonitor.isConnected }
        self.isLargeWidth = isLargeWidth
        self.windowAndScreenWidths = windowAndScreenWidths
    }

    var currentContext: UsageContext {
        UsageContext(hardwareKeyboard: isHardwareKeyboardConnected(), layout: isLargeWidth() ? .regular : .compact)
    }

    @MainActor
    var currentWindowMode: UsageContext.WindowMode {
        guard isPad, let widths = windowAndScreenWidths() else { return .fullScreen }
        return Self.windowMode(windowWidth: widths.window, screenWidth: widths.screen)
    }

    static func windowMode(windowWidth: CGFloat, screenWidth: CGFloat) -> UsageContext.WindowMode {
        // Allows for sub-point rounding between window and screen bounds.
        windowWidth < screenWidth - 1 ? .partial : .fullScreen
    }

    /// Any activation state: the usage context pixel reads this as the app enters the background.
    @MainActor
    private static func keyWindowWidths() -> (window: CGFloat, screen: CGFloat)? {
        guard let scene = UIApplication.shared.connectedScenes.lazy.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow ?? scene.windows.first else { return nil }
        return (window.bounds.width, scene.screen.bounds.width)
    }
}

extension UsageContext {

    /// Pixel parameter names, shared by every pixel that carries the context.
    enum ParameterName {
        static let hardwareKeyboard = "hardware_keyboard"
        static let layout = "layout"
        static let windowMode = "window_mode"
    }

    var parameters: [String: String] {
        [ParameterName.layout: layout.rawValue, ParameterName.hardwareKeyboard: String(hardwareKeyboard)]
    }
}

/// GameController reports the hardware keyboard reliably only on the main thread, so pixels fired elsewhere
/// read this copy, refreshed on each app activation and on keyboard connect and disconnect notifications.
///
/// The first read waits until the app becomes active: it starts GameController's device session, which can
/// block a background launch past the launch watchdog. Until then the keyboard reports as disconnected.
final class HardwareKeyboardMonitor {

    private let lock = NSLock()
    private let isConnectedNow: () -> Bool
    private var isKeyboardConnected = false
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default,
         isConnectedNow: @escaping () -> Bool = { GCKeyboard.coalesced != nil }) {
        self.isConnectedNow = isConnectedNow
        let names: [Notification.Name] = [UIApplication.didBecomeActiveNotification, .GCKeyboardDidConnect, .GCKeyboardDidDisconnect]
        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    var isConnected: Bool {
        lock.withLock { isKeyboardConnected }
    }

    /// Re-read rather than taking the notification's direction: another keyboard may still be attached.
    private func refresh() {
        let connected = isConnectedNow()
        lock.withLock { isKeyboardConnected = connected }
    }
}
