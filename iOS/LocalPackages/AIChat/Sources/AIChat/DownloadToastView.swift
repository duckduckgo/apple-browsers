//
//  DownloadToastView.swift
//  DuckDuckGo
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

import SwiftUI
import UIKit

private enum Constants {
    static let cornerRadius: CGFloat = 8
    static let backgroundColor: Color = .black
    static let textColor: Color = .white
    static let horizontalPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 100
    static let animationDuration: TimeInterval = 0.2
    static let toastVisibleDuration: TimeInterval = 3.0
}

struct DownloadToastView: View {
    let fileName: String
    let onShowButtonTapped: () -> Void

    var body: some View {
        HStack {
            Text(attributedString)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onShowButtonTapped) {
                Text(UserText.downloadToastShow)
                    .bold()
                    .foregroundColor(Constants.textColor)
            }
        }
        .padding()
        .background(Constants.backgroundColor)
        .cornerRadius(Constants.cornerRadius)
        .padding(.horizontal, Constants.horizontalPadding)
    }

    private var attributedString: AttributedString {
        var attributedString = AttributedString(String(format: UserText.downloadComplete, fileName))
        if let range = attributedString.range(of: fileName) {
            attributedString[range].font = .boldSystemFont(ofSize: UIFont.systemFontSize)
            attributedString[range].foregroundColor = Constants.textColor
        }
        return attributedString
    }
}

extension UIView {
    func presentDownloadToast(fileName: String, onShowButtonTapped: @escaping () -> Void) {
        let toastView = DownloadToastView(fileName: fileName, onShowButtonTapped: onShowButtonTapped)
        let hostingController = UIHostingController(rootView: toastView)

        hostingController.view.isUserInteractionEnabled = true
        hostingController.view.frame = CGRect(x: 0, y: bounds.height - Constants.bottomPadding, width: bounds.width, height: 50)

        addSubview(hostingController.view)

        hostingController.view.alpha = 0
        UIView.animate(withDuration: Constants.animationDuration) {
            hostingController.view.alpha = 1
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.toastVisibleDuration) {
                UIView.animate(withDuration: Constants.animationDuration) {
                    hostingController.view.alpha = 0
                } completion: { _ in
                    hostingController.view.removeFromSuperview()
                }
            }
        }
    }
}
