//
//  CredentialProviderActivatedView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Lottie

private struct ExtensionLottieView: UIViewRepresentable {
    let animationName: String

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: animationName)
        view.loopMode = .playOnce
        view.contentMode = .scaleAspectFit
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) { }
}

struct CredentialProviderActivatedView: View {

    let viewModel: CredentialProviderActivatedViewModel
    @State private var isAnimating = false

    var body: some View {
        NavigationView {

            VStack(spacing: 0) {

                ExtensionLottieView(animationName: "confirmation-prompt-128")
                    .frame(width: 128, height: 128)
                    .padding(.top, 48)

                Text(UserText.credentialProviderActivatedTitle)
                    .daxTitle2()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .padding(.top, 16)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    viewModel.launchDDGApp()
                } label: {
                    Text(UserText.credentialProviderActivatedButton)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 12)

            }
            .padding(.horizontal, 24)
            .navigationBarItems(trailing: Button(UserText.actionDone) {
                viewModel.dismiss()
            })
        }
    }
    
}

#Preview {
    CredentialProviderActivatedView(viewModel: CredentialProviderActivatedViewModel())
}
