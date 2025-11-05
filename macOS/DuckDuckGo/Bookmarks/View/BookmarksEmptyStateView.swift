//
//  BookmarksEmptyStateView.swift
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
import DesignResourcesKit

private struct ButtonWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DynamicWidthButtonStyle: ButtonStyle {
    let maxWidth: CGFloat?
    let defaultBackgroundColor: DesignSystemColor
    let pressedBackgroundColor: DesignSystemColor
    let textColor: DesignSystemColor

    func makeBody(configuration: Configuration) -> some View {
        let backgroundColor = configuration.isPressed ? pressedBackgroundColor : defaultBackgroundColor

        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(width: maxWidth, height: 28)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ButtonWidthPreferenceKey.self, value: geometry.size.width)
                }
            )
            .background(Color(designSystemColor: backgroundColor))
            .foregroundColor(Color(designSystemColor: textColor))
            .cornerRadius(5)
    }
}

public struct BookmarksEmptyStateView: View {
    @ObservedObject private var syncButtonModel = SyncDeviceButtonModel()
    @State private var maxButtonWidth: CGFloat = 0
    let content: BookmarksEmptyStateContent
    let onImportClicked: () -> Void
    let onSyncClicked: () -> Void

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let image = content.image {
                Image(nsImage: image)
                    .accessibilityIdentifier(BookmarksEmptyStateContent.imageAccessibilityIdentifier)
            }

            VStack(spacing: 8) {
                Text(content.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.labelColor))
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                    .accessibilityIdentifier(BookmarksEmptyStateContent.titleAccessibilityIdentifier)

                Text(content.description)
                    .font(.system(size: 13))
                    .foregroundColor(Color(.labelColor))
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                    .accessibilityIdentifier(BookmarksEmptyStateContent.descriptionAccessibilityIdentifier)
            }

            HStack(spacing: 10) {
                if !content.shouldHideSyncButton, syncButtonModel.shouldShowSyncButton {
                    Button(UserText.bookmarksEmptyStateSyncButtonTitle) {
                        onSyncClicked()
                    }
                    .buttonStyle(DynamicWidthButtonStyle(
                        maxWidth: maxButtonWidth > 0 ? maxButtonWidth : nil,
                        defaultBackgroundColor: .buttonsSecondaryFillDefault,
                        pressedBackgroundColor: .buttonsSecondaryFillPressed,
                        textColor: .buttonsSecondaryFillText
                    ))
                }
                if !content.shouldHideImportButton {
                    Button(UserText.bookmarksEmptyStateImportButtonTitle) {
                        onImportClicked()
                    }
                    .buttonStyle(DynamicWidthButtonStyle(
                        maxWidth: maxButtonWidth > 0 ? maxButtonWidth : nil,
                        defaultBackgroundColor: .buttonsPrimaryDefault,
                        pressedBackgroundColor: .buttonsPrimaryPressed,
                        textColor: .buttonsPrimaryText
                    ))
                }
            }
            .onPreferenceChange(ButtonWidthPreferenceKey.self) { width in
                maxButtonWidth = width
            }

            Spacer()
        }
        .frame(width: 300, height: 383)
    }
}

extension BookmarksEmptyStateView {
    public func embeddedInHostingView() -> NSHostingView<BookmarksEmptyStateView> {
        return NSHostingView(rootView: self)
    }
}
