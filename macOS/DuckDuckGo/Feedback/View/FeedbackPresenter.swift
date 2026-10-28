//
//  FeedbackPresenter.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

enum FeedbackPresenter {

    @MainActor
    static func presentFeedbackForm(preselectedFormOption: FeedbackViewController.FormOption? = nil) {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else {
            assertionFailure("FeedbackPresenter: Failed to present FeedbackWindow")
            return
        }

        let contentRect = NSRect(x: 0, y: 0, width: FeedbackWindow.Size.width, height: FeedbackWindow.Size.height)
        let feedbackWindow = FeedbackWindow(contentRect: contentRect,
                                            styleMask: [.titled, .closable, .fullSizeContentView],
                                            backing: .buffered,
                                            defer: true)
        feedbackWindow.titleVisibility = .hidden
        feedbackWindow.titlebarAppearsTransparent = true
        feedbackWindow.autorecalculatesKeyViewLoop = false
        feedbackWindow.isReleasedWhenClosed = false
        feedbackWindow.contentViewController = FeedbackViewController(nibName: nil, bundle: nil)

        feedbackWindow.feedbackViewController.preselectedFormOption = preselectedFormOption
        feedbackWindow.feedbackViewController.currentTab =
            parentWindowController.mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab
        parentWindowController.window?.beginSheet(feedbackWindow) { _ in }
    }

}
