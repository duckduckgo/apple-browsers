//
//  PasswordsWidgetView.swift
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
import WidgetKit
import DesignResourcesKit
import DesignResourcesKitIcons

struct PasswordsWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        DesignSystemWidgetContainerView {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    TintableImage(fullColor: UIImage(resource: .widgetPasswordIllustration),
                                  tintable: UIImage(resource: .widgetPasswordIllustrationTinted)) { $0 }
                        .accessibilityHidden(true)

                    Spacer()

                    Text(UserText.passwords)
                        .daxSubheadSemibold()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .makeAccentable()

                    HStack { Spacer() }
                }

                Spacer()
            }
        }
        .accessibilityLabel(Text(UserText.passwords))
    }
}
