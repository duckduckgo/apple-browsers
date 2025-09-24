//
//  Extensions.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

extension Color {

    static func forDomain(_ domain: String) -> Color {
        return Color(UIColor.forDomain(domain))
    }

}

// See https://stackoverflow.com/a/59228385/73479
extension View {

    @ViewBuilder func widgetContainerBackground() -> some View {
        let color = Color(designSystemColor: .background)
        if #available(iOSApplicationExtension 26.0, *) {
            containerBackground(for: .widget) {
            }
        } else if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                color
            }
        } else {
            background(color)
        }
    }

    func makeAccentable(_ isAccentable: Bool = true) -> some View {
        if #available(iOSApplicationExtension 16.0, *) {
            return self.widgetAccentable(isAccentable)
        } else {
            return self
        }
    }

    /// Hide or show the view based on a boolean value.
    ///
    /// Example for visibility:
    /// ```
    /// Text("Label")
    ///     .isHidden(true)
    /// ```
    ///
    /// Example for complete removal:
    /// ```
    /// Text("Label")
    ///     .isHidden(true, remove: true)
    /// ```
    ///
    /// - Parameters:
    ///   - hidden: Set to `false` to show the view. Set to `true` to hide the view.
    ///   - remove: Boolean value indicating whether or not to remove the view.
    @ViewBuilder func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
        } else {
            self
        }
    }

    /// Logically inverse of `isHidden`
    @ViewBuilder func isVisible(_ visible: Bool, remove: Bool = false) -> some View {
        self.isHidden(!visible, remove: remove)
    }

}

extension Image {

    /// Marks images as exempt from tint color overrides, such as favicons which should not have their color modified even when a tint color is set.
    @ViewBuilder func useFullColorRendering() -> some View {
        if #available(iOSApplicationExtension 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }

}

extension RoundedRectangle {

    @ViewBuilder
    func renderAwareBackgroundFill(_ color: Color = Color(designSystemColor: .backgroundTertiary)) -> some View {
        if #available(iOSApplicationExtension 17, *) {
            modifier(RenderingAwareFieldFillColor(color: color))
        } else {
            fill(color)
        }
    }

}

@available(iOSApplicationExtension 17, *)
private struct RenderingAwareFieldFillColor: ViewModifier {

    @Environment(\.widgetRenderingMode) var widgetRenderingMode

    let color: Color

    func body(content: Content) -> some View {
        if widgetRenderingMode == .fullColor {
            content.foregroundStyle(color)
        } else {
            // See https://www.figma.com/design/6bSIUkJP6bihfEApcidLS9/iOS-widgets-tinting?node-id=185-5961&t=MCToFbbAM3OtJCwN-0
            content.foregroundStyle(color.opacity(0.3))
        }
    }

}
