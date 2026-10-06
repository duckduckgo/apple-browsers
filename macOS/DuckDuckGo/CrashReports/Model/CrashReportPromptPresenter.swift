//
//  CrashReportPromptPresenter.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import CrashReportingShared

@MainActor
final class CrashReportPromptPresenter: NSObject {

    private enum Constants {
        static let initialContentRect = NSRect(x: 0, y: 0, width: 550, height: 427)
    }

    enum Response: Equatable {
        case allow, deny
    }

    let viewController = CrashReportPromptViewController()

    lazy var windowController: NSWindowController = {
        let window = NSWindow(contentRect: Constants.initialContentRect,
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: true)
        // Reusing the feedback form's "Report a Problem" title.
        window.title = UserText.reportProblemFormTitle
        window.autorecalculatesKeyViewLoop = false
        window.contentViewController = viewController
        return NSWindowController(window: window)
    }()

    func showPrompt(for crashReport: CrashReportPresenting) async -> Response {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            viewController.crashReport = crashReport
            viewController.userDidAnswerPrompt = { [weak self] response in
                self?.resumeContinuation(with: response)
            }

            // Set up window delegate to handle window closing
            windowController.window?.delegate = self
            windowController.showWindow(self)
            windowController.window?.center()
        }
    }

    private func resumeContinuation(with response: Response) {
        guard let continuation = continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(returning: response)
    }

    private var continuation: CheckedContinuation<Response, Never>?
}

// MARK: - NSWindowDelegate

extension CrashReportPromptPresenter: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // If window is closed without explicit user response, treat as deny
        resumeContinuation(with: .deny)
    }
}
