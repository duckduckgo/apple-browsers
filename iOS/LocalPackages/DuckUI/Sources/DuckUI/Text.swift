//
//  Text.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

public struct Label4Style: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private let design: Font.Design
    private let foregroundColorLight: Color
    private let foregroundColorDark: Color

    public init(design: Font.Design = .default, foregroundColorLight: Color = Color(designSystemColor: .textPrimary), foregroundColorDark: Color = Color(designSystemColor: .textPrimary)) {
        self.design = design
        self.foregroundColorLight = foregroundColorLight
        self.foregroundColorDark = foregroundColorDark
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(.callout, design: design))
            .foregroundColor(colorScheme == .light ? foregroundColorLight : foregroundColorDark)
    }
}

public struct Label4SubtitleStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private let design: Font.Design

    public init(design: Font.Design = .default) {
        self.design = design
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(.callout, design: design))
            .foregroundColor(Color(designSystemColor: .textSecondary))
    }
}

public extension View {

    func label4Style(design: Font.Design = .default, foregroundColorLight: Color = Color(designSystemColor: .textPrimary), foregroundColorDark: Color = Color(designSystemColor: .textPrimary)) -> some View {
        modifier(Label4Style(design: design, foregroundColorLight: foregroundColorLight, foregroundColorDark: foregroundColorDark))
    }
}

extension Font {
    init(uiFont: UIFont) {
        self = Font(uiFont as CTFont)
    }
}

// MARK: - Debug gallery

public struct TextStylesGallery: View {

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Label4Style — default") {
                    Text(verbatim: "Primary label using callout + textPrimary token.")
                        .label4Style()
                }

                section("Label4Style — monospaced design") {
                    Text(verbatim: "Primary label with monospaced design.")
                        .label4Style(design: .monospaced)
                }

                section("Label4Style — custom foregrounds") {
                    Text(verbatim: "Custom blue in light / orange in dark.")
                        .label4Style(
                            foregroundColorLight: .blue,
                            foregroundColorDark: .orange
                        )
                }

                section("Label4SubtitleStyle") {
                    Text(verbatim: "Subtitle label using callout + textSecondary token.")
                        .modifier(Label4SubtitleStyle())
                    Text(verbatim: "Subtitle label, monospaced design.")
                        .modifier(Label4SubtitleStyle(design: .monospaced))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color(designSystemColor: .background))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(designSystemColor: .textSecondary))
            content()
        }
    }
}

#if DEBUG
#Preview("Text styles / Light") {
    TextStylesGallery()
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
}

#Preview("Text styles / Dark") {
    TextStylesGallery()
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
}

#endif
