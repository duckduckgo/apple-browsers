//
//  DBPOptOutEmailComposer.swift
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

import MessageUI
import DataBrokerProtectionCore

public protocol DBPOptOutEmailComposing {
    @MainActor var canSendMail: Bool { get }
    @MainActor func compose(_ email: DBPUIOpenOptOutEmailRequest) async -> MFMailComposeResult
#if DBP_DEBUG_TOOLS
    @MainActor func simulateSend(_ email: DBPUIOpenOptOutEmailRequest) async -> Bool
#endif
}

final class DBPOptOutEmailComposer: NSObject, DBPOptOutEmailComposing {

    private weak var presentingViewController: UIViewController?
    var pendingCompose: CheckedContinuation<MFMailComposeResult, Never>?

    init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
    }

    @MainActor var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// Closing the dashboard also closes Mail without a delegate callback, so the request resolves as not sent here.
    @MainActor
    func presenterDidDisappear() {
        resolvePendingCompose(with: .cancelled)
    }

    @MainActor
    func compose(_ email: DBPUIOpenOptOutEmailRequest) async -> MFMailComposeResult {
        guard pendingCompose == nil, canSendMail, let presentingViewController = readyPresentingViewController else {
            return .failed
        }

        let composeViewController = MFMailComposeViewController()
        composeViewController.mailComposeDelegate = self
        composeViewController.isModalInPresentation = true
        composeViewController.setToRecipients([email.to])
        composeViewController.setSubject(email.subject)
        composeViewController.setMessageBody(email.body, isHTML: false)

        return await withCheckedContinuation { continuation in
            pendingCompose = continuation
            presentingViewController.present(composeViewController, animated: true)
        }
    }

#if DBP_DEBUG_TOOLS
    @MainActor
    func simulateSend(_ email: DBPUIOpenOptOutEmailRequest) async -> Bool {
        guard pendingCompose == nil, let presentingViewController = readyPresentingViewController else { return false }

        let result = await withCheckedContinuation { continuation in
            pendingCompose = continuation
            let alert = UIAlertController(title: "Simulate email send (debug)",
                                          message: "Mail isn't set up on this device.\n\nTo: \(email.to)\nSubject: \(email.subject)",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Simulate Send", style: .default) { [weak self] _ in self?.resolvePendingCompose(with: .sent) })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.resolvePendingCompose(with: .cancelled) })
            presentingViewController.present(alert, animated: true)
        }
        return result == .sent
    }
#endif
}

private extension DBPOptOutEmailComposer {
    @MainActor
    func resolvePendingCompose(with result: MFMailComposeResult) {
        guard let continuation = pendingCompose else { return }
        pendingCompose = nil
        continuation.resume(returning: result)
    }

    @MainActor
    var readyPresentingViewController: UIViewController? {
        guard let presentingViewController,
              presentingViewController.viewIfLoaded?.window != nil,
              !presentingViewController.isBeingDismissed,
              presentingViewController.presentedViewController == nil else {
            return nil
        }
        return presentingViewController
    }
}

extension DBPOptOutEmailComposer: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        let continuation = pendingCompose
        pendingCompose = nil
        controller.dismiss(animated: true) {
            continuation?.resume(returning: result)
        }
    }
}
