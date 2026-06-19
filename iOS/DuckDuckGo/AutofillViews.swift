//
//  AutofillViews.swift
//  DuckDuckGo
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

struct AutofillViews {

    static let loginPromptMinHeight: CGFloat = 200.0
    static let newUserMinHeight: CGFloat = 375.0
    static let saveLoginMinHeight: CGFloat = 310.0
    static let savePasswordMinHeight: CGFloat = 310.0
    static let updatePasswordMinHeight: CGFloat = 340.0
    static let updateUsernameMinHeight: CGFloat = 310.0
    static let saveCreditCardMinHeight: CGFloat = 375.0
    static let passwordGenerationMinHeight: CGFloat = 310.0
    static let emailSignupPromptMinHeight: CGFloat = 260.0
    static let deleteAllPromptMinHeight: CGFloat = 360.0
    static let zipImportPromptMinHeight: CGFloat = 360.0

    struct CloseButtonHeader: View {
        let action: () -> Void

        var body: some View {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        action()
                    } label: {
                        Image.close
                            .resizable()
                            .scaledToFit()
                            .frame(width: Const.Size.closeButtonSize, height: Const.Size.closeButtonSize)
                    }
                    .buttonStyle(CloseButtonStyle())
                    .padding(ContainerMetrics.closeButtonPadding - CloseButtonStyle.Constant.padding)
                }
                Spacer()
            }
        }
    }

    struct AppIconHeader: View {
        var body: some View {
            Image(.appDuckDuckGo32)
                .resizable()
                .frame(width: 48, height: 48)
        }
    }

    struct Headline: View {
        let title: String

        var body: some View {
            Text(title)
                .daxTitle3()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: Const.Size.maxWidth)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }


    struct Description: View {
        let text: String

        var body: some View {
            Text(text)
            .daxFootnoteRegular()
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Const.Size.maxWidth)
        }
    }

    struct SecureDescription: View {
        let text: String
        var showIcon: Bool = true

        var body: some View {
            (iconText + Text(text))
                .font(Font(UIFont.daxFootnoteRegular()))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Const.Size.maxWidth)
        }

        private var iconText: Text {
            if showIcon {
                Text("\(Image(uiImage: DesignSystemImages.Glyphs.Size12.lockSolid)) ").baselineOffset(-1.0)
            } else {
                Text("")
            }
        }
    }

    struct PrimaryButton: View {
        let title: String
        var image: Image?
        let action: () -> Void

        var body: some View {
            Button {
                action()
            } label: {
                HStack(spacing: 8) {
                    if let image {
                        image
                            .renderingMode(.template)
                    }
                    Text(title)
                        .daxButton()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    struct SecondaryButton: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .daxButton()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: Const.Size.maxWidth)
        }
    }

    struct TertiaryButton: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .daxButton()
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    struct LegacySpacerView: View {
        let height: CGFloat?
        let legacyHeight: CGFloat?

        init(height: CGFloat? = nil, legacyHeight: CGFloat? = nil) {
            self.height = height
            self.legacyHeight = legacyHeight
        }

        var body: some View {
            if #available(iOS 16.0, *) {
                Spacer()
                    .frame(height: height)
            } else {
                Spacer()
                    .frame(height: legacyHeight)
            }
        }
    }

    static func isIPhonePortrait(_ verticalSizeClass: UserInterfaceSizeClass?, _ horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        verticalSizeClass == .regular && horizontalSizeClass == .compact
    }

    static func isIPhoneLandscape(_ verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        verticalSizeClass == .compact
    }

    static func isIPad(_ verticalSizeClass: UserInterfaceSizeClass?, _ horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        verticalSizeClass == .regular && horizontalSizeClass == .regular
    }

    // We have specific layouts for the smaller iPhones
    static func isSmallFrame(_ frame: CGSize) -> Bool {
        frame.width > 0 && frame.width <= Const.Size.smallDevice
    }

    static func contentHeightExceedsScreenHeight(_ contentHeight: CGFloat) -> Bool {
        if #available(iOS 16.0, *) {
            let topSafeAreaInset = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?
                .safeAreaInsets
                .top ?? 0.0
            return contentHeight > UIScreen.main.bounds.size.height - topSafeAreaInset
        } else {
            return false
        }
    }

    static func maxWidthFor(title1: String, title2: String, font: UIFont) -> CGFloat {
        return max(title1.width(for: font), title2.width(for: font))
    }
}

extension View {
    @ViewBuilder
    func useScrollView(_ useScrollView: Bool, minHeight: CGFloat) -> some View {
        if useScrollView {
            ScrollView(showsIndicators: false) {
                self
            }
            .frame(minHeight: minHeight)
        } else {
            self
        }
    }
}

private enum Const {
    enum Size {
        static let closeButtonSize: CGFloat = 24.0
        static let smallDevice: CGFloat = 320.0
        static let maxWidth: CGFloat = 480.0
    }
}

private extension Image {
    static let close = Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AutofillViews.CloseButtonHeader(action: {})
            AutofillViews.AppIconHeader()
            AutofillViews.Headline(title: "Placeholder Title")
            AutofillViews.Description(text: "Body text goes here describing the autofill feature.")
            AutofillViews.SecureDescription(text: "Your data is encrypted and stored only on your device.")
            AutofillViews.PrimaryButton(title: "Primary Button", action: {})
            AutofillViews.SecondaryButton(title: "Secondary Button", action: {})
            AutofillViews.TertiaryButton(title: "Tertiary Button", action: {})
        }
        .padding()
    }
    .background(Color(designSystemColor: .background))
}
