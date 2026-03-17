//
//  MainWindow.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Cocoa
import Common
import Combine

final class MainWindow: NSWindow {

    static let minWindowWidth: CGFloat = 544
    static let firstResponderDidChangeNotification = Notification.Name("firstResponderDidChange")

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override var frameAutosaveName: NSWindow.FrameAutosaveName {
        return "MainWindow"
    }

    override func setFrameAutosaveName(_ name: NSWindow.FrameAutosaveName) -> Bool {
        return super.setFrameAutosaveName(self.frameAutosaveName)
    }

    private var semaphoreLightsManager: SemaphoreLightsManager?

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: true)

        setupWindow()
        semaphoreLightsManager = SemaphoreLightsManager(window: self)
        semaphoreLightsManager?.startObservingChanges()

        assert(AppVersion.runType != .unitTests, "MainWindow should not be created in unit tests")
    }

    // To avoid beep sounds, this keyDown method catches events that go through the
    // responder chain when no other responders process it
    override func keyDown(with event: NSEvent) {
        if event.keyEquivalent == [.command, "f"] {
            // beep on Cmd+F when Find In Page is unavailable
            super.keyDown(with: event)
            return
        }
        super.performKeyEquivalent(with: event)
    }

    private func setupWindow() {
        allowsToolTipsWhenApplicationIsInactive = false
        autorecalculatesKeyViewLoop = false
        isReleasedWhenClosed = false
        animationBehavior = .documentWindow
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = .fullScreenPrimary

        // Setting minimum width to fit the wide NTP search bar
        minSize = .init(width: Self.minWindowWidth, height: 0)
    }

    /// The overridden method sends `firstResponderDidChange` notification on first responder change
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // The only reliable way to detect NSTextField is the first responder
        defer {
            // Send it after the first responder has been set on the super class so that window.firstResponder matches correctly
            NotificationCenter.default.post(name: MainWindow.firstResponderDidChangeNotification, object: self)
        }
        return super.makeFirstResponder(responder)
    }

    override func endEditing(for object: Any?) {
        if case .leftMouseUp = NSApp.currentEvent?.type,
           object is AddressBarTextEditor {
            // prevent deactivation of Address Bar on Toolbar click
            return
        }

        super.endEditing(for: object)
    }

    /// Used to observe `childWindows` property which is non-KVO-compliant by-default
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        willChangeValue(for: \.childWindows)
        super.addChildWindow(childWin, ordered: place)
        didChangeValue(for: \.childWindows)
    }
    /// Used to observe `childWindows` property which is non-KVO-compliant by-default
    override func removeChildWindow(_ childWin: NSWindow) {
        willChangeValue(for: \.childWindows)
        super.removeChildWindow(childWin)
        didChangeValue(for: \.childWindows)
    }

    /// Makes custom Tab Bar visible for VoiceOver (Accessibility Inspector) as the direct window‘s child
    /// (`accessibilityEnabled` and `isAccessibilityElement` are set in `MainWindowController.moveTabBarView(toTitlebarView:)`)
    override func accessibilityChildren() -> [Any]? {
        guard var children = super.accessibilityChildren() else { return nil }

        guard let mainViewController = self.contentViewController as? MainViewController else {
            assertionFailure(
                "MainWindow contentViewController must be MainViewController, but is \(String(describing: self.contentViewController))"
            )
            return children
        }
        lazy var insertionPoint: Int = {
            let buttons = children.enumerated().filter({
                ($0.element as? NSAccessibilityProtocol)?.accessibilityRole() == .button
            })
            // semaphore buttons should be present
            guard buttons.count > 3 else { return 0 }
            guard let insertionPoint = buttons.prefix(3).last?.offset else { return 0 }

            return insertionPoint + 1
        }()

        let tabBarViewController = mainViewController.tabBarViewController
        if !children.contains(where: { $0 as AnyObject === tabBarViewController.view }) {
            // Insert `TabBarViewController.view` as the window‘s AX child after the semaphore buttons if it‘s not there already
            children.insert(tabBarViewController.view, at: insertionPoint)
        }
        return children
    }
}

// MARK: - SemaphoreLightsManager

class SemaphoreLightsManager {

    private var cancellables = [AnyCancellable]()
    private weak var window: NSWindow?
    var buttonTypesAndLocations: [NSWindow.ButtonType: NSPoint] = [
        .closeButton:       NSPoint(x: 17, y: 14),
        .miniaturizeButton: NSPoint(x: 37, y: 14),
        .zoomButton:        NSPoint(x: 57, y: 14)
    ]


    init(window: NSWindow) {
        self.window = window
    }

    deinit {
        stopListeningToNotifications()
    }

    func startObservingChanges() {
        layoutTrafficLights()
        startListeningToNotifications()
        subscribeToTrafficLightsFrames()
    }
}

private extension SemaphoreLightsManager {

    func startListeningToNotifications() {
        let observedNotificationNames = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didResizeNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        for name in observedNotificationNames {
            NotificationCenter.default.addObserver(self, selector: #selector(processWindowNotification), name: name, object: window)
        }
    }

    func stopListeningToNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    func subscribeToTrafficLightsFrames() {
        guard let closeButton = window?.standardWindowButton(.closeButton) else {
            return
        }

        closeButton
            .publisher(for: \.frame)
            .sink { [weak self] _ in
                self?.layoutTrafficLights()
            }
            .store(in: &cancellables)
    }

    func layoutTrafficLights() {
        if Thread.isMainThread {
            layoutTrafficLightsOnMainThread()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.layoutTrafficLightsOnMainThread()
        }
    }

    private func layoutTrafficLightsOnMainThread() {
        for (type, origin) in buttonTypesAndLocations {
            guard let button = window?.standardWindowButton(type), button.frame.origin != origin else {
                continue
            }

            button.frame.origin = origin
        }
    }
}

private extension SemaphoreLightsManager {

    @objc
    func processWindowNotification(_ note: Notification) {
        layoutTrafficLights()
    }
}
