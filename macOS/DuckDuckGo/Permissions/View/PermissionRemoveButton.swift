//
//  PermissionRemoveButton.swift
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
import SwiftUI

/// The "X" that removes a saved permission, shared by the permission center popover and Settings → Website Permissions.
struct PermissionRemoveButton: View {
    private enum Constants {
        static let size: CGFloat = 24
        static let glyphSize: CGFloat = 10
    }

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: Constants.glyphSize, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .frame(width: Constants.size, height: Constants.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverHighlightButtonStyle())
    }
}

/// A plain button that draws a rounded highlight behind its label while the pointer is over it.
/// The highlight is suppressed while the button is disabled.
struct HoverHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlightButton(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct HoverHighlightButton: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered && isEnabled ? Color(.buttonMouseOver) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
