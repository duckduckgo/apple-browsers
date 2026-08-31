//
//  PermissionDialogCard.swift
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

private enum PermissionDialogCardConstants {
    static let cornerRadius: CGFloat = 32
    static let padding: CGFloat = 14
    static let verticalMargin: CGFloat = 20
}

struct PermissionDialogCard<Content: View>: View {

    @Environment(\.colorScheme) private var colorScheme

    private let width: CGFloat
    private let accessibilityIdentifier: String
    private let content: Content

    init(width: CGFloat,
         accessibilityIdentifier: String,
         @ViewBuilder content: () -> Content) {
        self.width = width
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.2)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: PermissionDialogCardConstants.verticalMargin)
                        card
                        Spacer(minLength: PermissionDialogCardConstants.verticalMargin)
                    }
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var card: some View {
        content
            .padding(PermissionDialogCardConstants.padding)
            .frame(width: width)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: PermissionDialogCardConstants.cornerRadius, style: .continuous))
            .shadow(color: shadowColors.primary, radius: 16, x: 0, y: 8)
            .shadow(color: shadowColors.secondary, radius: 6, x: 0, y: 2)
    }

    private var shadowColors: (primary: Color, secondary: Color) {
        colorScheme == .light
        ? (.black.opacity(0.08), .black.opacity(0.10))
        : (.black.opacity(0.20), .black.opacity(0.16))
    }

}
