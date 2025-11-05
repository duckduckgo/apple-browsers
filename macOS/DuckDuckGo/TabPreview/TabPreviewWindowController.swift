//
//  TabPreviewWindowController.swift
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
import os.log

final class TabPreviewWindowController: NSWindowController {

    static let width: CGFloat = 280
    static let padding: CGFloat = 2
    static let bottomPadding: CGFloat = 40
    static let delay: CGFloat = 1

    private var previewTimer: Timer? {
        willSet {
            previewTimer?.invalidate()
        }
    }
    private var hideTimer: Timer?
    private var lastHideTime: Date?

    var isPresented: Bool {
        window?.isVisible == true || previewTimer != nil
    }

    // swiftlint:disable force_cast
    var tabPreviewViewController: TabPreviewViewController {
        return self.window!.contentViewController as! TabPreviewViewController
    }
    // swiftlint:enable force_cast

    init() {
        super.init(window: Self.loadWindow())
    }

    required init?(coder: NSCoder) {
        fatalError("\(Self.self): Bad initializer")
    }

    deinit {
#if DEBUG
        // Check that the window deallocates
        window?.ensureObjectDeallocated(after: 1.0, do: .interrupt)

        // Check that the view controller deallocates
        tabPreviewViewController.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    private static func loadWindow() -> NSWindow {
        let tabPreviewViewController = TabPreviewViewController()

        let window = NSWindow(contentRect: CGRect(x: 294, y: 313, width: 280, height: 58), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        window.contentViewController = tabPreviewViewController

        window.allowsToolTipsWhenApplicationIsInactive = false
        window.autorecalculatesKeyViewLoop = false
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.animationBehavior = .utilityWindow
        window.setAccessibilityEnabled(false)
        window.setAccessibilityElement(false)

        return window
    }

    func show(parentWindow: NSWindow, topLeftPointInWindow: CGPoint, shouldDisplayPreviewAfterDelay: @escaping () -> Bool) {
        Logger.tabPreview.log("Showing tab preview")

        // Invalidate hide timer if it exists
        hideTimer?.invalidate()

        guard let childWindows = parentWindow.childWindows,
              let tabPreviewWindow = self.window else {
            Logger.tabPreview.error("Showing tab preview window failed")
            return
        }

        if childWindows.contains(tabPreviewWindow) {
            Logger.tabPreview.log("Preview already shown: moving to \(topLeftPointInWindow.x)x\(topLeftPointInWindow.y)")
            layout(topLeftPoint: parentWindow.convertPoint(toScreen: topLeftPointInWindow))
            return
        }

        // Check time elapsed since last hide
        if let lastHide = lastHideTime, Date().timeIntervalSince(lastHide) < Self.delay {
            // Show immediately if less than 1.5 seconds have passed
            presentPreview(in: parentWindow, at: topLeftPointInWindow)
        } else {
            // Set up a new timer for normal delayed presentation
            previewTimer = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { [weak self, weak parentWindow] _ in
                guard shouldDisplayPreviewAfterDelay(), let self, let parentWindow else {
                    Logger.tabPreview.info("preview not needed anymore after delay")
                    return
                }
                presentPreview(in: parentWindow, at: topLeftPointInWindow)
            }
        }
    }

    private func presentPreview(in parentWindow: NSWindow, at topLeftPointInWindow: NSPoint) {
        Logger.tabPreview.log("Presenting tab preview")

        guard let window, parentWindow.isVisible else {
            Logger.tabPreview.error("can‘t present preview")
            return
        }

        parentWindow.addChildWindow(window, ordered: .above)
        self.layout(topLeftPoint: parentWindow.convertPoint(toScreen: topLeftPointInWindow))
    }

    func hide(withDelay delay: Bool, allowQuickRedisplay: Bool) {
        Logger.tabPreview.log("Hiding tab preview allowQuickRedisplay:\(allowQuickRedisplay) delay:\(delay)")

        previewTimer = nil
        guard window?.isVisible == true else {
            Logger.tabPreview.info("window is not visible: return early")
            return
        }

        if delay {
            // Set up a new timer to hide the preview after 0.05 seconds
            // It makes the transition from one preview to another more fluent
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                self?.removePreview(allowQuickRedisplay: allowQuickRedisplay)
            }
        } else {
            // Hide the preview immediately
            removePreview(allowQuickRedisplay: allowQuickRedisplay)
        }
    }

    private func removePreview(allowQuickRedisplay: Bool) {
        Logger.tabPreview.log("Removing tab preview allowQuickRedisplay:\(allowQuickRedisplay)")

        guard let window else {
            Logger.tabPreview.error("no window")
            lastHideTime = nil
            return
        }

        let parentWindow = window.parent

        parentWindow?.removeChildWindow(window)
        window.orderOut(nil)

        // Record the hide time
        lastHideTime = allowQuickRedisplay ? Date() : nil
    }

    private func layout(topLeftPoint: NSPoint) {
        guard let window else { return }
        var topLeftPoint = topLeftPoint

        // Make sure preview is presented within screen
        if let screenVisibleFrame = window.screen?.visibleFrame {
            topLeftPoint.x = min(topLeftPoint.x, screenVisibleFrame.origin.x + screenVisibleFrame.width - window.frame.width)
            topLeftPoint.x = max(topLeftPoint.x, screenVisibleFrame.origin.x)

            let windowHeight = window.frame.size.height
            if topLeftPoint.y <= windowHeight + screenVisibleFrame.origin.y {
                topLeftPoint.y = topLeftPoint.y + windowHeight + Self.bottomPadding
            }
        }

        window.setFrameTopLeftPoint(topLeftPoint)
    }

}

extension TabPreviewWindowController {

    @objc func suggestionWindowOpenNotification(_ notification: Notification) {
        hide(withDelay: false, allowQuickRedisplay: false)
    }

}
