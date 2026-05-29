//
//  AIChatHistoryViewController.swift
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

import UIKit

/// Placeholder container for the native Duck.ai chat-history sheet.
final class AIChatHistoryViewController: UIViewController {

    static func makePresentableSheet() -> UIViewController {
        let content = AIChatHistoryViewController()
        let navigationController = UINavigationController(rootViewController: content)
        navigationController.modalPresentationStyle = .automatic
        return navigationController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = UserText.aiChatRecentChatsTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: UserText.navigationTitleDone,
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
}
