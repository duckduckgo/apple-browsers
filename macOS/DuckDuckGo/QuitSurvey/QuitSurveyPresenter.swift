//
//  QuitSurveyPresenter.swift
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
import PrivacyConfig
import SwiftUI
import History

/// Presents the quit survey UI as a sheet or standalone window.
@MainActor
final class QuitSurveyPresenter {
    private let windowControllersManager: WindowControllersManager
    private let persistor: QuitSurveyPersistor
    private let historyCoordinating: HistoryCoordinating?
    private let faviconManaging: FaviconManagement?
    private let featureFlagger: FeatureFlagger

    init(windowControllersManager: WindowControllersManager,
         persistor: QuitSurveyPersistor,
         featureFlagger: FeatureFlagger,
         historyCoordinating: HistoryCoordinating? = nil,
         faviconManaging: FaviconManagement? = nil) {
        self.windowControllersManager = windowControllersManager
        self.persistor = persistor
        self.featureFlagger = featureFlagger
        self.historyCoordinating = historyCoordinating
        self.faviconManaging = faviconManaging
    }

    /// Shows the quit survey and asynchronously waits for user completion.
    func showSurvey() async {
        await withCheckedContinuation { continuation in
            var quitSurveyWindow: NSWindow?
            var isResumed = false

            let resumeContinuation = {
                guard !isResumed else { return }
                isResumed = true
                continuation.resume()
            }

            let surveyView = QuitSurveyFlowView(
                persistor: persistor,
                featureFlagger: featureFlagger,
                historyCoordinating: historyCoordinating,
                faviconManaging: faviconManaging,
                onQuit: {
                    if let parentWindow = quitSurveyWindow?.sheetParent {
                        parentWindow.endSheet(quitSurveyWindow!)
                    } else {
                        quitSurveyWindow?.close()
                    }
                    resumeContinuation()
                },
                onResize: { width, height in
                    guard let window = quitSurveyWindow else { return }
                    // For sheets, use origin: .zero - macOS handles sheet positioning automatically
                    let newFrame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
                    window.setFrame(newFrame, display: true, animate: false)
                }
            )

            let controller = QuitSurveyViewController(rootView: surveyView)
            quitSurveyWindow = NSWindow(contentViewController: controller)

            guard let window = quitSurveyWindow else {
                continuation.resume()
                return
            }

            // Set up window close observation to resume continuation if window is closed via close button
            let windowDelegate = QuitSurveyWindowDelegate(onWindowWillClose: resumeContinuation)
            window.delegate = windowDelegate
            // Retain the delegate to prevent it from being deallocated
            objc_setAssociatedObject(window, "quitSurveyDelegate", windowDelegate, .OBJC_ASSOCIATION_RETAIN)

            window.styleMask.remove(.resizable)
            let windowRect = NSRect(
                x: 0,
                y: 0,
                width: QuitSurveyViewController.Constants.initialWidth,
                height: QuitSurveyViewController.Constants.initialHeight
            )
            window.setFrame(windowRect, display: true)

            // Show as sheet on the main window, or as standalone window if no main window
            if let parentWindowController = windowControllersManager.lastKeyMainWindowController,
               let parentWindow = parentWindowController.window {
                parentWindow.beginSheet(window) { _ in }
            } else {
                // Fallback: show as a centered window
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

}

// MARK: - Window Delegate

@MainActor
private final class QuitSurveyWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowWillClose: () -> Void

    init(onWindowWillClose: @escaping () -> Void) {
        self.onWindowWillClose = onWindowWillClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose()
    }
}
