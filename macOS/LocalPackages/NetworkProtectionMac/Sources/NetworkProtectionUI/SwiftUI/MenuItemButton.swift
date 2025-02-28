//
//  MenuItemButton.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI

struct MenuItemButton: View {

    private struct Detail {
        let text: String
        let color: Color
    }

    @Environment(\.colorScheme) private var colorScheme
    private let icon: Image?
    private let title: String
    private let titleColor: Color
    private let detail: Detail?
    private let highlightColor: Color
    private let action: () async -> Void

    private let highlightAnimationStepSpeed = AnimationConstants.highlightAnimationStepSpeed

    @State private var isHovered = false
    @State private var animatingTap = false

    init(icon: Image? = nil, title: String, titleColor: Color, highlightColor: Color, action: @escaping () async -> Void) {

        self.icon = icon
        self.title = title
        self.titleColor = titleColor
        self.detail = nil
        self.highlightColor = highlightColor
        self.action = action
    }

    init(icon: Image? = nil, title: String, titleColor: Color, detail: String, detailColor: Color, highlightColor: Color, action: @escaping () async -> Void) {
        self.icon = icon
        self.title = title
        self.titleColor = titleColor
        self.detail = Detail(text: detail, color: detailColor)
        self.highlightColor = highlightColor
        self.action = action
    }

    var body: some View {
        Button(action: {
            buttonTapped()
        }) {
            HStack(spacing: 4) {
                if let icon {
                    icon
                        .foregroundColor(isHovered ? highlightColor : titleColor)
                }
                Text(title)
                    .foregroundColor(isHovered ? highlightColor : titleColor)

                if let detail {
                    Text(detail.text)
                        .foregroundColor(isHovered ? highlightColor : detail.color)
                }

                Spacer()
            }.padding([.top, .bottom], 3)
                .padding([.leading, .trailing], 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            buttonBackground(highlighted: isHovered)
        )
        .contentShape(Rectangle())
        .cornerRadius(4)
        .onTapGesture {
            buttonTapped()
        }
        .onHover { hovering in
            if !animatingTap {
                isHovered = hovering
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func buttonBackground(highlighted: Bool) -> some View {
        if highlighted {
            return AnyView(
                VisualEffectView(material: .selection, blendingMode: .withinWindow, state: .active, isEmphasized: true))
        } else {
            return AnyView(Color.clear)
        }
    }

    private func buttonTapped() {
        animatingTap = true
        isHovered = false

        DispatchQueue.main.asyncAfter(deadline: .now() + highlightAnimationStepSpeed) {
            isHovered = true

            DispatchQueue.main.asyncAfter(deadline: .now() + highlightAnimationStepSpeed) {
                animatingTap = false

                Task {
                    await action()
                }
            }
        }
    }
}

private enum Opacity {
    static func detailText(colorScheme: ColorScheme) -> Double {
        colorScheme == .light ? Double(0.6) : Double(0.5)
    }
}
