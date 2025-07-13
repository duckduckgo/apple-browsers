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

final class CrashReportPromptPresenter {
    enum Response: Equatable {
        case allow, deny
    }

    lazy var windowController: NSWindowController = {
        let storyboard = NSStoryboard(name: "CrashReports", bundle: nil)
        return storyboard.instantiateController(identifier: "CrashReportPromptWindowController")
    }()

    var viewController: CrashReportPromptViewController {
        // swiftlint:disable force_cast
        return windowController.contentViewController as! CrashReportPromptViewController
        // swiftlint:enable force_cast
    }

    @MainActor
    func showPrompt(for crashReport: CrashReportPresenting) async -> Response {
        await withCheckedContinuation { continuation in
            viewController.crashReport = crashReport
            viewController.userDidAnswerPrompt = { response in
                continuation.resume(returning: response)
            }

            windowController.showWindow(self)
            windowController.window?.center()
        }
    }

}
