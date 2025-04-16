//
//  OpenMultipleTabsWarningDialog.swift
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

import SwiftUIExtensions

final class OpenMultipleTabsWarningDialogModel: ObservableObject {
    enum Response {
        case unknown, cancel, open
    }

    let count: Int
    private(set) var response: Response = .unknown

    init(count: Int) {
        self.count = count
    }

    func cancel() {
        response = .cancel
    }

    func open() {
        response = .open
    }
}

struct OpenMultipleTabsWarningDialog: ModalView {

    @ObservedObject var model: OpenMultipleTabsWarningDialogModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(.logo)
                .resizable()
                .frame(width: 58, height: 58)
                .padding(8)

            VStack(spacing: 12) {
                Text(UserText.openMultipleTabsAlertTitle(count: model.count))
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 15).weight(.semibold))

                Text(UserText.openMultipleTabsAlertMessage)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 13))
            }
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Button {
                    model.cancel()
                    dismiss()
                } label: {
                    Text(UserText.cancel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0))

                Button {
                    model.open()
                    dismiss()
                } label: {
                    Text(UserText.open)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0))

            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

#Preview {
    OpenMultipleTabsWarningDialog(model: .init(count: 52))
}
