//
//  WarningView.swift
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
import SwiftUIExtensions
import DesignResourcesKit

struct WarningView: View {

    enum Constants {
        static let backgroundCornerRadius = 16.0
        static let legacyBackgroundCornerRadius = 8.0
    }

    let model: Model

    /// Captured at init so it stays stable for the view's lifetime.
    let isAppRebranded: Bool

    init(model: Model, isAppRebranded: Bool = DesignSystemRebrand.isAppRebranded()) {
        self.model = model
        self.isAppRebranded = isAppRebranded
    }

    private var cornerRadius: CGFloat {
        isAppRebranded ? Constants.backgroundCornerRadius : Constants.legacyBackgroundCornerRadius
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(.warningColored)

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.message)
                            .makeSelectable()
                            .multilineText()
                            .foregroundColor(Color(.defaultText))

                        if let actionTitle = model.actionTitle,
                           let action = model.action {
                            Button(actionTitle, action: action)
                                .buttonStyle(DismissActionButtonStyle(textColor: Color(.defaultText)))
                                .keyboardShortcut(.defaultAction)
                                .padding(.top, 3)
                        }
                    }

                    Spacer()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.alertBubbleBackground))
            )
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
    }
}
