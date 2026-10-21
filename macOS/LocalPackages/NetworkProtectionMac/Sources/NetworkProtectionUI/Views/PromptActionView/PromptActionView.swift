//
//  PromptActionView.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit

fileprivate extension View {
    func applyStepTitleAttributes() -> some View {
        self.font(.system(size: 13).weight(.bold))
            .foregroundColor(Color(.defaultText))
    }

    func applyStepDescriptionAttributes() -> some View {
        self.font(.system(size: 13))
            .foregroundColor(Color(.defaultText))
    }

}

struct PromptActionView: View {

    enum Constants {
        static let backgroundCornerRadius = 16.0
        static let legacyBackgroundCornerRadius = 6.0
    }

    @Environment(\.colorScheme) var colorScheme

    // MARK: - Model

    let model: Model

    /// Captured at init so it stays stable for the view's lifetime.
    let isAppRebranded: Bool

    // MARK: - Initializers

    init(model: Model, isAppRebranded: Bool = DesignSystemRebrand.isAppRebranded()) {
        self.model = model
        self.isAppRebranded = isAppRebranded
    }

    // MARK: - View

    private var cornerRadius: CGFloat {
        isAppRebranded ? Constants.backgroundCornerRadius : Constants.legacyBackgroundCornerRadius
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(model.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40)

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.title)
                            .applyStepTitleAttributes()
                            .multilineText()

                        model.description.reduce(Text("")) { previous, fragment in
                            var newText = Text(fragment.text)

                            if fragment.isEmphasized {
                                newText = newText.fontWeight(.semibold)
                            }

                            return previous + newText
                        }
                        .applyStepDescriptionAttributes()
                        .multilineText()

                        Button(model.actionTitle, action: model.action)
                            .keyboardShortcut(.defaultAction)
                            .padding(.top, 3)
                    }

                    Spacer()
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)

            if let actionScreenshot = model.actionScreenshot {
                // This is done this way because the change was introduced as a hotfix
                // for macOS Sequoia and we want to avoid breakage
                if #available(macOS 15, *) {
                    Image(actionScreenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(actionScreenshot)
                }
            }
        }
        .cornerRadius(8)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                .stroke(Color(.onboardingStepBorder), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                        .fill(Color(.onboardingStepBackground))
                ))
    }
}
