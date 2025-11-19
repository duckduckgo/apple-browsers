//
//  DefaultBrowserAndDockPromptNotificationPresenter.swift
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
//  This presenter is responsible solely for the logic of preparing and
//  requesting presentation of Default Browser & Dock Prompt related
//  system notifications. It does not decide when to show them nor does it
//  open any feedback UI yet – that will be wired later.
//

import Foundation
import UserNotifications
import AppKit

// MARK: - Protocol

protocol DefaultBrowserAndDockPromptNotificationPresenting: AnyObject {
    func requestAuthorization()
    func showInactiveUserPromptNotification()
    func handleNotificationResponse(for identifier: DefaultBrowserAndDockPromptNotificationIdentifier) async
}

enum DefaultBrowserAndDockPromptNotificationIdentifier: String {
    case inactiveUserFeedbackRequest = "com.duckduckgo.inactive-user.feedback-request.notification"
}

// MARK: - Presenter

final class DefaultBrowserAndDockPromptNotificationPresenter: NSObject, DefaultBrowserAndDockPromptNotificationPresenting {

    private let userNotificationCenter: UNUserNotificationCenter
    private let reportABrowserProblemPresenter: (Any?, ProblemCategory?, SubCategory?) -> Void

    init(userNotificationCenter: UNUserNotificationCenter = .current(),
         reportABrowserProblemPresenter: @escaping (Any?, ProblemCategory?, SubCategory?) -> Void) {
        self.userNotificationCenter = userNotificationCenter
        self.reportABrowserProblemPresenter = reportABrowserProblemPresenter
        super.init()

        requestAuthorization()
    }

    // MARK: Authorization

    func requestAuthorization() {
        requestAlertAuthorization()
    }

    private func requestAlertAuthorization(completionHandler: ((Bool) -> Void)? = nil) {
        userNotificationCenter.requestAuthorization(options: .alert) { authorized, _ in
            completionHandler?(authorized)
        }
    }

    // MARK: Notification response

    @MainActor func handleNotificationResponse(for identifier: DefaultBrowserAndDockPromptNotificationIdentifier) {
        switch identifier {
        case .inactiveUserFeedbackRequest:
            openPromotionalMessagesFeedbackForm()
        }
    }

    // MARK: Inactive User Feedback Request

    func showInactiveUserPromptNotification() {
        let content = UNMutableNotificationContent()
        content.title = UserText.setAsDefaultAndAddToDockInactiveUserNotificationTitle
        content.body = UserText.setAsDefaultAndAddToDockInactiveUserNotificationBody

        if #available(macOS 12, *) {
            content.interruptionLevel = .active
        }

        let identifier = DefaultBrowserAndDockPromptNotificationIdentifier.inactiveUserFeedbackRequest.rawValue
        showNotification(identifier: identifier, content: content)
    }

    @MainActor private func openPromotionalMessagesFeedbackForm() {
        let category = ProblemCategory.allCategories.first(where: { $0.isSomethingElseCategory })
        let subcategory = category?.subcategories.first(where: { $0.isPromotionalMessagesSubcategory })
        reportABrowserProblemPresenter(nil, category, subcategory)
    }

    // MARK: Presentation helper

    private func showNotification(identifier: String, content: UNNotificationContent) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: .none)
        requestAlertAuthorization { [weak self] authorized in
            guard let self, authorized else { return }
            userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
            userNotificationCenter.add(request)
        }
    }
}
