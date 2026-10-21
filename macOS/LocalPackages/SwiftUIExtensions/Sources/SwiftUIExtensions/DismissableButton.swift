//
//  DismissableButton.swift
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

public struct DismissableButton: View {
    private let title: String
    private let dismissButtonImage: NSImage
    private let backgroundColor: Color
    private let mainAction: @MainActor () -> Void
    private let dismissAction: @MainActor () -> Void

    public init(title: String, dismissButtonImage: NSImage, backgroundColor: Color, mainAction: @escaping () -> Void, dismissAction: @escaping () -> Void) {
        self.title = title
        self.dismissButtonImage = dismissButtonImage
        self.backgroundColor = backgroundColor
        self.mainAction = mainAction
        self.dismissAction = dismissAction
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Main action area (fills remaining width)
            Button(action: mainAction) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .padding(.leading, 12)
            }
            .buttonStyle(.plain) // your existing style

            // Divider between the two tap targets
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 0)

            // Independent X button
            Button(action: dismissAction) {
                Image(nsImage: dismissButtonImage)
                    .padding(6)
                    .contentShape(Rectangle()) // reliable hit target
            }
            .buttonStyle(.plain) // keep it visually neutral
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor) // match your style’s fill
        )
        .padding(0)
    }
}
