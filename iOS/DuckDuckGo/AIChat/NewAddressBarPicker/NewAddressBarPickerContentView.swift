//
//  NewAddressBarPickerContentView.swift
//  DuckDuckGo
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
import UIComponents
import DesignResourcesKit
import DuckUI
import Lottie
import AIChat

struct NewAddressBarPickerContentView: View {
    let aiChatSettings: AIChatSettingsProvider
    let onDismiss: () -> Void

    init(
        aiChatSettings: AIChatSettingsProvider,
        onDismiss: @escaping () -> Void
    ) {
        self.aiChatSettings = aiChatSettings
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 20) {
            ContentView()
            CTAView(
                aiChatSettings: aiChatSettings,
                onDismiss: onDismiss
            )
                .frame(maxWidth: 440)
                .padding(.horizontal, 32)
        }
        .background(Color(designSystemColor: .background))
    }
}

private struct ContentView: View {
    var body: some View {
        ZStack {
            Color(designSystemColor: .background)

            backgroundView
            VStack {
                topSpacer
                headerView
                    .frame(width: 300)
                    .padding(.top, 64)
                Spacer()
                AnimationView()
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var topSpacer: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            Spacer()
        } else {
            EmptyView()
        }
    }

    var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BadgeView(text: UserText.settingsItemNewBadge)
                Text(UserText.newAddressBarPickerTitle)
                    .textCase(.uppercase)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(baseColor: .red50))
            }
            .padding(.bottom, 8)

            Text(UserText.newAddressBarPickerSubtitle)
                .daxTitle1()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text(UserText.newAddressBarPickerDescription)
                .daxCaption()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
        }
    }

    var backgroundView: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(designSystemColor: .background), location: 0.2),
                Gradient.Stop(color: Color(designSystemColor: .accent), location: 1.8),
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.8, y: 1.8)
        )
    }
}

private struct AnimationView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Code required to loop specific parts of the animation
    /// https://app.asana.com/1/137249556945/project/1207822763512188/task/1211197237823963?focus=true
    @State private var hasPlayedIntro = false

    private enum AnimationFrame {
        static let introStart: AnimationFrameTime = 0
        static let introEnd: AnimationFrameTime = 30
        static let loopStart: AnimationFrameTime = 31
        static let defaultEnd: AnimationFrameTime = 100 /// Fallback in case lottieAnimationView is nil
    }

    var body: some View {
        let animation = AddressBarPickerAnimation.animation(
            for: UIDevice.current.userInterfaceIdiom,
            colorScheme: colorScheme
        )

        Lottie.LottieView(animation: .named(animation.rawValue))
            .imageProvider(AddressBarPickerAnimationImageProvider(
                colorScheme: colorScheme,
                deviceIdiom: UIDevice.current.userInterfaceIdiom
            ))
            .configure(configureLottieAnimation)
            .scaledToFit()
            .id("\(animation.rawValue)-\(colorScheme)")
    }

    private func configureLottieAnimation(_ lottieAnimationView: LottieAnimationView) {
        let endFrame = lottieAnimationView.animation?.endFrame ?? AnimationFrame.defaultEnd

        if hasPlayedIntro {
            playLoopAnimation(in: lottieAnimationView, endFrame: endFrame)
        } else {
            playIntroAnimation(in: lottieAnimationView, endFrame: endFrame)
        }
    }

    private func playIntroAnimation(in animationView: LottieAnimationView, endFrame: AnimationFrameTime) {
        animationView.play(
            fromFrame: AnimationFrame.introStart,
            toFrame: AnimationFrame.introEnd,
            loopMode: .playOnce
        ) { [self] completed in
            guard completed else { return }

            hasPlayedIntro = true
            playLoopAnimation(in: animationView, endFrame: endFrame)
        }
    }

    private func playLoopAnimation(in animationView: LottieAnimationView, endFrame: AnimationFrameTime ) {
        animationView.play(
            fromFrame: AnimationFrame.loopStart,
            toFrame: endFrame,
            loopMode: .loop
        )
    }
}

private enum AddressBarPickerAnimation: String {
    case iPhoneDark = "toggle-ios-dark"
    case iPhoneLight = "toggle-ios-light"
    case iPadDark = "toggle-ipad-dark"
    case iPadLight = "toggle-ipad-light"

    static func animation(for device: UIUserInterfaceIdiom, colorScheme: ColorScheme) -> AddressBarPickerAnimation {
        switch (device, colorScheme) {
        case (.pad, .dark):
            return .iPadDark
        case (.pad, .light):
            return .iPadLight
        case (_, .dark):
            return .iPhoneDark
        case (_, .light):
            return .iPhoneLight
        case (_, _):
            return .iPhoneLight
        }
    }
}

private struct CTAView: View {
    let aiChatSettings: AIChatSettingsProvider
    let onDismiss: () -> Void
    @State private var selectedOption: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            RadioButtonView(
                options: [
                    UserText.newAddressBarPickerSearchOnly,
                    UserText.newAddressBarPickerSearchAndAI
                ],
                selectedIndex: selectedOption,
                configuration: RadioButtonConfiguration(layout: UIDevice.current.userInterfaceIdiom == .pad ? .horizontal : .vertical)
            ) { _, selectedIndex in
                if let index = selectedIndex {
                    self.selectedOption = index
                }
            }
            .padding(.bottom, 16)

            Button {
                handleConfirmation()
            } label: {
                Text(UserText.newAddressBarPickerConfirm)
                    .daxButton()
                    .foregroundStyle(Color(designSystemColor: .accentContentPrimary))

            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, 8)

            Button {
                onDismiss()
            } label: {
                Text(UserText.newAddressBarPickerNotNow)
                    .daxButton()
                    .foregroundStyle(Color(designSystemColor: .accent))

            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.bottom, 16)

            Text(UserText.newAddressBarPickerFooter)
                .daxCaption()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .padding(.bottom, bottomPadding)
        }
    }

    private var bottomPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 0
    }

    private func handleConfirmation() {
        // selectedOption 0 = Search Only (disable AI search input)
        // selectedOption 1 = Search and AI (enable AI search input)
        let enableAISearch = (selectedOption == 1)
        aiChatSettings.enableAIChatSearchInputUserSettings(enable: enableAISearch)
        onDismiss()
    }
}

// MARK: - Animation Image Provider

final class AddressBarPickerAnimationImageProvider: AnimationImageProvider, Equatable {
    private let colorScheme: ColorScheme
    private let deviceIdiom: UIUserInterfaceIdiom
    
    init(colorScheme: ColorScheme, deviceIdiom: UIUserInterfaceIdiom) {
        self.colorScheme = colorScheme
        self.deviceIdiom = deviceIdiom
    }
    
    static func == (lhs: AddressBarPickerAnimationImageProvider, rhs: AddressBarPickerAnimationImageProvider) -> Bool {
        return lhs.colorScheme == rhs.colorScheme && lhs.deviceIdiom == rhs.deviceIdiom
    }
    
    func imageForAsset(asset: ImageAsset) -> CGImage? {
        let imageName: String
        
        switch asset.name {
        case "img_0.png":
            imageName = "ab-animation-blur"
        case "img_1.png":
            imageName = "ab-animation-pill"
        default:
            return nil
        }
        
        return UIImage(named: imageName)?.cgImage
    }

}
