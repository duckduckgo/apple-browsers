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

    private var trafficLightsCancellables = [AnyCancellable]()

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: true)

        setupWindow()
        startListeningToNotifications()
        subscribeToTrafficLightsFrames()
        assert(AppVersion.runType != .unitTests, "MainWindow should not be created in unit tests")
    }

    deinit {
        stopListeningToNotifications()
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

        layoutTrafficLights()
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

    // MARK: - Traffic Lights Repositioning

    private func startListeningToNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(windowDidResize), name: NSWindow.didResizeNotification, object: self)
        notificationCenter.addObserver(self, selector: #selector(windowDidExitFullScreen), name: NSWindow.didExitFullScreenNotification, object: self)
        notificationCenter.addObserver(self, selector: #selector(windowWillEnterFullScreen), name: NSWindow.willEnterFullScreenNotification, object: self)
        notificationCenter.addObserver(self, selector: #selector(windowWillExitFullScreen), name: NSWindow.willExitFullScreenNotification, object: self)
        notificationCenter.addObserver(self, selector: #selector(windowDidEnterFullScreen), name: NSWindow.didEnterFullScreenNotification, object: self)
        notificationCenter.addObserver(self, selector: #selector(windowDidDeminiaturize), name: NSWindow.didDeminiaturizeNotification, object: self)
    }

    private func stopListeningToNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    private func subscribeToTrafficLightsFrames() {
        guard let closeButton = standardWindowButton(.closeButton) else {
            return
        }

        closeButton
            .publisher(for: \.frame)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.layoutTrafficLights()
            }
            .store(in: &trafficLightsCancellables)
    }

    override func becomeKey() {
        super.becomeKey()
        layoutTrafficLights()
    }

    override func resignKey() {
        super.resignKey()
        layoutTrafficLights()
    }

    override var maxSize: NSSize {
        didSet {
            layoutTrafficLights()
        }
    }

    override var minSize: NSSize {
        didSet {
            layoutTrafficLights()
        }
    }
}

// MARK: - Notification Handlers

private extension MainWindow {

    @objc
    func windowDidExitFullScreen(_ note: Notification) {
        layoutTrafficLights()
    }

    @objc
    func windowWillEnterFullScreen(_ note: Notification) {
        layoutTrafficLights()
    }

    @objc
    func windowWillExitFullScreen(_ note: Notification) {
        layoutTrafficLights()
    }

    @objc
    func windowDidEnterFullScreen(_ note: Notification) {
        layoutTrafficLights()
    }

    @objc
    func windowDidResize(_ note: Notification) {
        layoutTrafficLights()
    }

    @objc
    func windowDidDeminiaturize(_ note: Notification) {
        layoutTrafficLights()
    }
}

private extension MainWindow {

    func layoutTrafficLights() {
        let originY: CGFloat = 14
        let buttonLocations: [NSPoint] = [
            NSPoint(x: 17, y: originY),
            NSPoint(x: 37, y: originY),
            NSPoint(x: 57, y: originY)
        ]

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton ]

        for (type, origin) in zip(buttonTypes, buttonLocations) {
            guard let button = standardWindowButton(type), button.frame.origin != origin else {
                continue
            }

            button.frame.origin = origin
        }
    }
}
