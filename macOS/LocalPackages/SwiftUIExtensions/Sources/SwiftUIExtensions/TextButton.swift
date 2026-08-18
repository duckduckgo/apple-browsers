//
//  TextButton.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public typealias LinkButton = TextButton
public struct TextButton: View {

    public let title: String
    public let fontSize: CGFloat
    public let fontWeight: Font.Weight
    public let action: () -> Void

    /// Explicit color supplied by the caller. When `nil`, the rebrandable link color is resolved in `body`
    /// from the environment palette, so it tracks theme changes.
    private let explicitTextColor: Color?

    @Environment(\.designSystemPalette) private var palette

    public init(_ title: String, textColor: Color? = nil, fontSize: CGFloat = NSFont.systemFontSize, weight: Font.Weight = .regular, action: @escaping () -> Void) {
        self.title = title
        self.explicitTextColor = textColor
        self.fontSize = fontSize
        self.fontWeight = weight
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize))
                .fontWeight(fontWeight)
                .foregroundColor(explicitTextColor ?? .rebrandableLink(palette: palette))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}

public struct IconButton: View {
    public let action: () -> Void
    public let icon: NSImage

    public init(icon: NSImage, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(nsImage: icon)
         }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}
