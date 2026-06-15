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

import Common
import FoundationExtensions
import Foundation
import SwiftUI

struct MenuItemButton: View {

    private struct Detail {
        let text: String
        let color: Color
    }

    private struct Confirmation {
        let successIcon: Image?
        let successTitle: String
        let failureIcon: Image?
        let failureTitle: String
    }

    private enum ConfirmationState: Equatable {
        case idle
        case success
        case failure
    }

    @Environment(\.colorScheme) private var colorScheme
    private let icon: Image?
    private let title: String
    private let titleColor: Color
    private let detail: Detail?
    private let highlightColor: Color
    private let confirmation: Confirmation?
    private let action: () async -> Bool

    private let highlightAnimationStepSpeed = AnimationConstants.highlightAnimationStepSpeed
    private let confirmationAnimation = Animation.easeInOut(duration: 0.18)
    private let confirmationResetDelay: TimeInterval = 2.0

    @State private var isHovered = false
    @State private var animatingTap = false
    @State private var isPerformingAction = false
    @State private var confirmationState = ConfirmationState.idle

    init(icon: Image? = nil, title: String, titleColor: Color, highlightColor: Color, action: @escaping () async -> Void) {

        self.icon = icon
        self.title = title
        self.titleColor = titleColor
        self.detail = nil
        self.highlightColor = highlightColor
        self.confirmation = nil
        self.action = {
            await action()
            return true
        }
    }

    init(icon: Image? = nil,
         title: String,
         titleColor: Color,
         highlightColor: Color,
         successIcon: Image? = nil,
         successTitle: String,
         failureIcon: Image? = nil,
         failureTitle: String,
         action: @escaping () async -> Bool) {

        self.icon = icon
        self.title = title
        self.titleColor = titleColor
        self.detail = nil
        self.highlightColor = highlightColor
        self.confirmation = Confirmation(
            successIcon: successIcon,
            successTitle: successTitle,
            failureIcon: failureIcon,
            failureTitle: failureTitle
        )
        self.action = action
    }

    init(icon: Image? = nil, title: String, titleColor: Color, detail: String, detailColor: Color, highlightColor: Color, action: @escaping () async -> Void) {
        self.icon = icon
        self.title = title
        self.titleColor = titleColor
        self.detail = Detail(text: detail, color: detailColor)
        self.highlightColor = highlightColor
        self.confirmation = nil
        self.action = {
            await action()
            return true
        }
    }

    var body: some View {
        Button(action: {
            buttonTapped()
        }) {
            HStack(spacing: 4) {
                if let currentIcon {
                    currentIcon
                        .foregroundColor(isHovered ? highlightColor : titleColor)
                        .transition(.opacity)
                }
                Text(currentTitle)
                    .foregroundColor(isHovered ? highlightColor : titleColor)
                    .transition(.opacity)
                    .id(currentTitle)

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
        .cornerRadius(AppVersion.isLiquidGlassSupported ? 7 : 4)
        .animation(confirmationAnimation, value: confirmationState)
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

    private var currentIcon: Image? {
        guard let confirmation else {
            return icon
        }

        switch confirmationState {
        case .idle:
            return icon
        case .success:
            return confirmation.successIcon
        case .failure:
            return confirmation.failureIcon
        }
    }

    private var currentTitle: String {
        guard let confirmation else {
            return title
        }

        switch confirmationState {
        case .idle:
            return title
        case .success:
            return confirmation.successTitle
        case .failure:
            return confirmation.failureTitle
        }
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
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        animatingTap = true
        isHovered = false

        DispatchQueue.main.asyncAfter(deadline: .now() + highlightAnimationStepSpeed) {
            isHovered = true

            DispatchQueue.main.asyncAfter(deadline: .now() + highlightAnimationStepSpeed) {
                animatingTap = false

                Task {
                    let succeeded = await action()
                    await MainActor.run {
                        isPerformingAction = false
                        showConfirmation(succeeded: succeeded)
                    }
                }
            }
        }
    }

    private func showConfirmation(succeeded: Bool) {
        guard confirmation != nil else {
            return
        }

        let newState: ConfirmationState = succeeded ? .success : .failure

        withAnimation(confirmationAnimation) {
            confirmationState = newState
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + confirmationResetDelay) {
            guard confirmationState == newState else {
                return
            }

            withAnimation(confirmationAnimation) {
                confirmationState = .idle
            }
        }
    }
}

private enum Opacity {
    static func detailText(colorScheme: ColorScheme) -> Double {
        colorScheme == .light ? Double(0.6) : Double(0.5)
    }
}
