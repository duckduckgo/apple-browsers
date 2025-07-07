//
//  UIView+Extension.swift
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

#if os(iOS)
import UIKit
import SwiftUI

extension UIView {

    private enum ToastConstants {
        static let bottomPadding: CGFloat = 100
        static let height: CGFloat = 50
        static let fadeAnimationDuration: TimeInterval = 0.2
        static let visibleDuration: TimeInterval = 3.0
    }

    func showDownloadCompletionToast(for fileName: String, onButtonTapped: @escaping () -> Void) {
        let message = createDownloadCompletionMessage(for: fileName)
        displayToast(with: message, buttonTitle: UserText.downloadToastShow, onButtonTapped: onButtonTapped)
    }

    func showDownloadFailedToast() {
        var message = AttributedString(UserText.downloadFailed)
        message.foregroundColor = .white
        displayToast(with: message, buttonTitle: "", onButtonTapped: nil)
    }

    private func createDownloadCompletionMessage(for fileName: String) -> AttributedString {
        var attributedMessage = AttributedString(String(format: UserText.downloadComplete, fileName))
        attributedMessage.foregroundColor = .white

        if let fileNameRange = attributedMessage.range(of: fileName) {
            attributedMessage[fileNameRange].font = .boldSystemFont(ofSize: UIFont.systemFontSize)
        }
        return attributedMessage
    }

    private func displayToast(with message: AttributedString, buttonTitle: String, onButtonTapped: (() -> Void)?) {
        let toastView = createToastView(with: message, buttonTitle: buttonTitle, onButtonTapped: onButtonTapped)
        animateToastAppearance(toastView)
    }

    private func createToastView(with message: AttributedString, buttonTitle: String, onButtonTapped: (() -> Void)?) -> UIView {
        let toastView = ToastView(message: message, buttonTitle: buttonTitle, onShowButtonTapped: onButtonTapped)
        let hostingController = UIHostingController(rootView: toastView)
        hostingController.view.isUserInteractionEnabled = true
        hostingController.view.frame = CGRect(x: 0,
                                              y: bounds.height - ToastConstants.bottomPadding,
                                              width: bounds.width,
                                              height: ToastConstants.height)
        addSubview(hostingController.view)
        return hostingController.view
    }

    private func animateToastAppearance(_ toastView: UIView) {
        toastView.alpha = 0
        UIView.animate(withDuration: ToastConstants.fadeAnimationDuration) {
            toastView.alpha = 1
        } completion: { _ in
            self.scheduleToastDisappearance(toastView)
        }
    }

    private func scheduleToastDisappearance(_ toastView: UIView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + ToastConstants.visibleDuration) {
            UIView.animate(withDuration: ToastConstants.fadeAnimationDuration) {
                toastView.alpha = 0
            } completion: { _ in
                toastView.removeFromSuperview()
            }
        }
    }
}
#endif
