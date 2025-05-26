//
//  OnboardingBorderedButton.swift
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

public struct OnboardingBorderedButton<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content
    let action: () -> Void

    public init(
        maxHeight: CGFloat = OnboardingStyles.ListButtonStyle.defaultMaxHeight,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) {
        self.maxHeight = maxHeight
        self.content = content()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(OnboardingStyles.ListButtonStyle(maxHeight: maxHeight))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .inset(by: 0.5)
                .stroke(.blue, lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingBorderedButton { Text(verbatim: "Hello World!!!") } action: {}
}
