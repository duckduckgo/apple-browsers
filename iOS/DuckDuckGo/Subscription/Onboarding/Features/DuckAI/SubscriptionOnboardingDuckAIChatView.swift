//
//  SubscriptionOnboardingDuckAIChatView.swift
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

import SwiftUI
import WebKit
import DesignResourcesKit
import DesignResourcesKitIcons

/// A full-screen modal hosting the Duck.ai web chat, launched from the Duck.ai onboarding screen's
/// "Start Duck.ai Chat" button. The view model persists the chosen model on Start, before this opens.
/// Prototype-grade: a bare `WKWebView` loading `duck.ai` with no shared session/cookies — so whether the
/// persisted model actually reaches the web chat is unverified; the production entry point is
/// `AIChatViewControllerManager`.
struct SubscriptionOnboardingDuckAIChatView: View {
    let onClose: () -> Void

    private enum Metrics {
        static let barPadding: CGFloat = 16
    }

    private static let chatURL = URL(string: "https://duck.ai")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                        .renderingMode(.template)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }
                .accessibilityLabel(UserText.subscriptionOnboardingDuckAIChatCloseButton)
            }
            .padding(Metrics.barPadding)

            DuckAIChatWebView(url: Self.chatURL)
        }
        .background(Color(designSystemColor: .surface).ignoresSafeArea())
    }
}

private struct DuckAIChatWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
