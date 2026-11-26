//
//  UpdatePromptView.swift
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

import DesignResourcesKit
import DuckUI
import SwiftUI
import UIKit

/// Presents the update prompt as an alert-style card over whatever is on screen.
final class UpdatePromptHostingController: UIHostingController<UpdatePromptView> {

    init(step: UpdatePromptStep, onUpdate: @escaping () -> Void, onNotNow: @escaping () -> Void) {
        weak var weakSelf: UpdatePromptHostingController?
        let view = UpdatePromptView(isLastReminder: step == .last,
                                    onUpdate: {
                                        onUpdate()
                                        weakSelf?.dismiss(animated: true)
                                    },
                                    onNotNow: {
                                        onNotNow()
                                        weakSelf?.dismiss(animated: true)
                                    })
        super.init(rootView: view)
        weakSelf = self
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
    }
}

struct UpdatePromptView: View {

    let isLastReminder: Bool
    let onUpdate: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            // Same dimming as the other alert-style cards, such as the Duck.ai on-device model prompt.
            Color.black
                .opacity(0.2)
                .ignoresSafeArea()

            // Scrolls when large text makes the card taller than the screen.
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: 20)
                        card
                            .frame(maxWidth: 340)
                            .padding(.horizontal, 24)
                        Spacer(minLength: 20)
                    }
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityAction(.escape, onNotNow)
    }

    private var card: some View {
        VStack(spacing: 20) {
            Image("RemoteMessageAppUpdate")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(UserText.updatePromptTitle)
                    .daxHeadline()
                    .accessibilityAddTraits(.isHeader)
                Text(isLastReminder ? UserText.updatePromptBodyLast : UserText.updatePromptBody)
                    .daxBodyRegular()
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundColor(Color(designSystemColor: .textPrimary))

            VStack(spacing: 12) {
                Button(UserText.updatePromptUpdate, action: onUpdate)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("UpdatePrompt.update")
                Button(UserText.updatePromptNotNow, action: onNotNow)
                    .buttonStyle(SecondaryFillButtonStyle())
                    .accessibilityIdentifier("UpdatePrompt.notNow")
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Color(designSystemColor: .backgroundSheets)))
    }
}
