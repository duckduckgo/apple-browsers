//
//  SessionRestorePromptView.swift
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
import SwiftUIExtensions

struct SessionRestorePromptView: View {

    enum Const {
        static let width: CGFloat = 320
    }

    @ObservedObject var model: SessionRestorePromptViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Image(.browserError128)
                .padding(.bottom, 8)

            Text(UserText.sessionRestorePromptTitle)
                .font(.title3)
                .bold()
                .padding(.bottom, 12)

            Text(UserText.sessionRestorePromptMessage)
                .multilineText()
                .font(.body)
                .padding(.bottom, 8)

            Text(UserText.sessionRestorePromptExplanation)
                .multilineText()
                .font(.body)
                .padding(.bottom, 20)

            HStack {
                Button {
                    model.startFresh()
                    dismiss()
                } label: {
                    Text(UserText.sessionRestorePromptButtonReject)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0))

                Button {
                    model.restoreSession()
                    dismiss()
                } label: {
                    Text(UserText.sessionRestorePromptButtonAccept)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(width: Const.width)
        .background(Color(.interfaceBackground))
    }
}
