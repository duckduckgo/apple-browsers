//
//  AutofillExtensionSettingsActivationView.swift
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
import DesignResourcesKit
import DuckUI

struct AutofillExtensionSettingsActivationView: View {

    @Environment(\.dismiss) var dismiss
    @State private var isAnimating = false

    var body: some View {
        NavigationView {

            VStack(spacing: 0) {

                AnimationView(isAnimating: $isAnimating)

                Text(UserText.autofillExtensionActivationTitle)
                    .daxTitle2()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .padding(.top, 16)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(UserText.autofillExtensionActivationDoneButtonTitle)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 12)

            }
            .padding(.horizontal, 24)
            .onFirstAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAnimating = true
                }
            }
        }
    }

    private struct AnimationView: View {
        @Binding var isAnimating: Bool

        var body: some View {
            LottieView(
                lottieFile: "confirmation-prompt-128",
                loopMode: .mode(.repeat(1.0)),
                isAnimating: $isAnimating
            )
            .frame(width: 128, height: 128)
            .padding(.top, 64)
        }
    }

}

#Preview {
    AutofillExtensionSettingsActivationView()
}
