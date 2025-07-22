//
//  ThankYouView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import Lottie
import SwiftUI
import SwiftUIExtensions

struct ThankYouView: View {
    var onClose: () -> Void
    var onSeeWhatsNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack(spacing: 12) {
                DaxHeartAnimation()
                    .frame(width: 64, height: 64)

                Text("Thanks for your feedback!")
                    .systemTitle2()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding([.leading, .trailing], 24)

            // Link section
            VStack(alignment: .leading, spacing: 16) {
                Text("Feedback like yours directly influences our product updates and improvements.")
                    .systemLabel(color: .textSecondary)
                    .multilineText()
                    .multilineTextAlignment(.leading)
                    .padding([.leading, .trailing], 24)

                Button {
                    onSeeWhatsNew()
                } label: {
                    HStack(spacing: 3) {
                        Text("See what's new in DuckDuckGo")
                            .systemLabel(color: .init(baseColor: .blue60))

                        Image(nsImage: DesignSystemImages.Glyphs.Size12.open)
                            .foregroundColor(.init(baseColor: .blue60))
                    }
                }
                .buttonStyle(.plain)
                .padding([.leading, .trailing], 24)

                Spacer()

                Divider()
                    .background(Color(baseColor: .gray20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)

                // Close button
                Button {
                    onClose()
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DismissActionButtonStyle())
                .padding([.leading, .trailing], 24)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DaxHeartAnimation: NSViewRepresentable {
    private let animation: LottieAnimation?
    private let animationView = LottieAnimationView()

    init() {
        self.animation = LottieAnimation.named("pictogramDaxHeart")
    }

    func makeNSView(context: Context) -> some NSView {
        let container = NSView()
        animationView.animation = animation
        animationView.contentMode = .scaleAspectFit
        animationView.clipsToBounds = false
        animationView.loopMode = .playOnce

        container.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalToConstant: 64),
            animationView.widthAnchor.constraint(equalToConstant: 64),
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        animationView.play()

        return container
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
    }
}
