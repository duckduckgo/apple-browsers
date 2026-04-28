//
//  SaveLoginView.swift
//  DuckDuckGo
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
import Common
import DuckUI
import BrowserServicesKit
import DesignResourcesKit
import DesignResourcesKitIcons

struct SaveLoginView: View {
    enum LayoutType {
        case newUser
        case saveLogin
        case savePassword
        case updateUsername
        case updatePassword
    }
    @State var frame: CGSize = .zero
    @ObservedObject var viewModel: SaveLoginViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var orientation = UIDevice.current.orientation
    @State private var bottomSafeArea: CGFloat = 0

    private var layoutType: LayoutType {
        viewModel.layoutType
    }

    private var usernameDisplayString: String {
        AutofillInterfaceUsernameTruncator.truncateUsername(viewModel.username, maxLength: 50)
    }

    var body: some View {
        GeometryReader { geometry in
            makeBodyView(geometry)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            orientation = UIDevice.current.orientation
        }
    }
    
    private func makeBodyView(_ geometry: GeometryProxy) -> some View {
        DispatchQueue.main.async {
            self.frame = geometry.size
            self.bottomSafeArea = geometry.safeAreaInsets.bottom
        }

        return ZStack {
            AutofillViews.CloseButtonHeader(action: viewModel.cancelButtonPressed)
                .padding(.top, closeButtonExtraPadding)
                .offset(x: horizontalPadding - closeButtonExtraPadding)
                .zIndex(1)

            innerContent
                .padding(.bottom, max(Const.Size.bodyBottomPadding - bottomSafeArea, 0))
                .fixedSize(horizontal: false, vertical: shouldFixSize)
                .background(GeometryReader { proxy -> Color in
                    DispatchQueue.main.async { viewModel.contentHeight = proxy.size.height }
                    return Color.clear
                })
                .useScrollView(shouldUseScrollView(), minHeight: frame.height)
        }
        .padding(.horizontal, horizontalPadding)
    }

    var shouldFixSize: Bool {
        AutofillViews.isIPhonePortrait(verticalSizeClass, horizontalSizeClass) || AutofillViews.isIPad(verticalSizeClass, horizontalSizeClass)
    }

    private func shouldUseScrollView() -> Bool {
        var useScrollView: Bool = false

        if #available(iOS 16.0, *) {
            useScrollView = AutofillViews.contentHeightExceedsScreenHeight(viewModel.contentHeight)
        } else {
            useScrollView = viewModel.contentHeight > frame.height
        }

        return useScrollView
    }

    // MARK: - Per-Variant Layouts

    @ViewBuilder
    private var innerContent: some View {
        switch layoutType {
        case .newUser:
            VStack {
                Spacer(minLength: Const.Size.topPadding)
                AutofillViews.AppIconHeader()
                Spacer(minLength: Const.Size.contentSpacing)
                AutofillViews.Headline(title: UserText.autofillSaveLoginTitleNewUser)
                Spacer(minLength: Const.Size.headlineToContentSpacing)
                AutofillViews.SecureDescription(text: UserText.autofillSaveLoginSecurityMessage)
                Spacer(minLength: Const.Size.contentSpacing)
                featuresView().padding([.bottom], Const.Size.featuresListPadding)
                onboardingCtaView()
            }

        case .saveLogin, .savePassword:
            VStack {
                Spacer(minLength: Const.Size.topPadding)
                AutofillViews.AppIconHeader()
                Spacer(minLength: Const.Size.contentSpacing)
                AutofillViews.Headline(title: UserText.autofillSaveLoginTitleNewUser)
                Spacer(minLength: Const.Size.headlineToContentSpacing)
                AutofillViews.SecureDescription(text: UserText.autofillSaveLoginSecurityMessage)
                Spacer(minLength: Const.Size.contentSpacing)
                standardCtaView(title: UserText.autofillSavePasswordSaveCTA)
            }

        case .updatePassword:
            VStack {
                Spacer(minLength: Const.Size.topPadding)
                AutofillViews.AppIconHeader()
                Spacer(minLength: Const.Size.contentSpacing)
                AutofillViews.Headline(title: UserText.autofillUpdatePassword(for: usernameDisplayString))
                Spacer(minLength: Const.Size.headlineToContentSpacing)
                AutofillViews.SecureDescription(text: UserText.autoUpdatePasswordMessage)
                Spacer(minLength: Const.Size.contentSpacing)
                standardCtaView(title: UserText.autofillUpdatePasswordSaveCTA)
            }

        case .updateUsername:
            VStack {
                Spacer(minLength: Const.Size.topPadding)
                AutofillViews.AppIconHeader()
                Spacer(minLength: Const.Size.contentSpacing)
                AutofillViews.Headline(title: UserText.autofillUpdateUsernameTitle)
                Spacer(minLength: Const.Size.headlineToContentSpacing)
                Text(verbatim: viewModel.usernameTruncated)
                    .font(Const.Fonts.userInfo)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                Spacer(minLength: Const.Size.contentSpacing)
                standardCtaView(title: UserText.autofillUpdateUsernameSaveCTA)
            }
        }
    }

    // MARK: - Features List

    @ViewBuilder
    private func featuresView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(UserText.autofillOnboardingKeyFeaturesTitle)
                    .font(Font.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .frame(width: 255, alignment: .top)
            }
            .padding(.vertical, Const.Size.featuresListVerticalSpacing)
            .frame(maxWidth: .infinity, alignment: .center)
            Rectangle()
                .fill(Color(designSystemColor: .lines))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: Const.Size.featuresListVerticalSpacing) {
                featuresListItem(
                    image: Image(uiImage: DesignSystemImages.Color.Size24.autofill),
                    title: UserText.autofillOnboardingKeyFeaturesSignInsTitle,
                    subtitle: UserText.autofillOnboardingKeyFeaturesSignInsDescription
                )
                featuresListItem(
                    image: Image(uiImage: DesignSystemImages.Color.Size24.lock),
                    title: UserText.autofillOnboardingKeyFeaturesSecureStorageTitle,
                    subtitle: viewModel.secureStorageDescription
                )
                featuresListItem(
                    image: Image(uiImage: DesignSystemImages.Color.Size24.sync),
                    title: UserText.autofillOnboardingKeyFeaturesSyncTitle,
                    subtitle: UserText.autofillOnboardingKeyFeaturesSyncDescription
                )
            }
            .padding(.horizontal, Const.Size.featuresListPadding)
            .padding(.top, Const.Size.featuresListTopPadding)
            .padding(.bottom, Const.Size.featuresListPadding)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cornerRadius(Const.Size.featuresListBorderCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Const.Size.featuresListBorderCornerRadius)
                .inset(by: 0.5)
                .stroke(Color(designSystemColor: .lines), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func featuresListItem(image: Image, title: String, subtitle: String) -> some View {
        let titleFont = Font(UIFont.daxSubheadSemibold())
        let subtitleFont = Font(UIFont.daxSubheadRegular())

        HStack(alignment: .top, spacing: Const.Size.featuresListItemHorizontalSpacing) {
            image.frame(width: Const.Size.featuresListItemImageWidthHeight, height: Const.Size.featuresListItemImageWidthHeight)
            VStack(alignment: .leading, spacing: Const.Size.featuresListItemVerticalSpacing) {
                Text(title)
                    .font(titleFont)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - CTA Views

    /// CTA buttons for onboarding flows
    ///
    private func onboardingCtaView() -> some View {
        VStack(spacing: Const.Size.ctaVerticalSpacing) {
            AutofillViews.PrimaryButton(title: UserText.autofillSavePasswordSaveCTA,
                                        action: viewModel.save)
            dismissButton
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        switch viewModel.dismissExperimentCohort {
        case .variant1:
            AutofillViews.TertiaryButton(title: UserText.autofillSaveLoginNotNowCTA,
                                         action: viewModel.cancelButtonPressed)
        case .variant2:
            AutofillViews.TertiaryButton(title: UserText.autofillSaveLoginNeverPromptCTA,
                                         action: viewModel.neverPrompt)
        case .control, nil:
            AutofillViews.TertiaryButton(title: UserText.autofillSaveLoginNoThanksCTA,
                                         action: viewModel.cancelButtonPressed)
        }
    }

    /// CTA buttons for non-onboarding flows
    ///
    private func standardCtaView(title: String) -> some View {
        VStack(spacing: Const.Size.ctaVerticalSpacing) {
            AutofillViews.PrimaryButton(title: title,
                                        action: viewModel.save)
            AutofillViews.TertiaryButton(title: UserText.autofillSaveLoginNeverPromptCTA,
                                         action: viewModel.neverPrompt)
        }
    }

    // iOS 26 needs some extra padding due to its very large corner radii
    private var closeButtonExtraPadding: CGFloat {
        if #available(iOS 26, *) {
            return 10
        } else {
            return 0
        }
    }

    private var horizontalPadding: CGFloat {
        if AutofillViews.isIPhonePortrait(verticalSizeClass, horizontalSizeClass) {
            if AutofillViews.isSmallFrame(frame) {
                return Const.Size.closeButtonOffsetPortraitSmallFrame
            } else {
                return Const.Size.closeButtonOffsetPortrait
            }
        } else {
            return Const.Size.closeButtonOffset
        }
    }
}

private enum Const {
    enum Fonts {
        static let userInfo = Font.system(.footnote).weight(.bold)
    }

    enum Size {
        static let closeButtonOffset: CGFloat = 48.0
        static let closeButtonOffsetPortrait: CGFloat = 44.0
        static let closeButtonOffsetPortraitSmallFrame: CGFloat = 16.0
        static let topPadding: CGFloat = 56.0
        static let contentSpacing: CGFloat = 24.0
        static let headlineToContentSpacing: CGFloat = 8.0
        static let ctaVerticalSpacing: CGFloat = 8.0
        static let bodyBottomPadding: CGFloat = 24.0
        static let featureListItemIconGap: CGFloat = 8.0
        static let featuresListItemImageWidthHeight: CGFloat = 24.0
        static let featuresListItemHorizontalSpacing: CGFloat = 12.0
        static let featuresListItemVerticalSpacing: CGFloat = 2.0
        static let featuresListVerticalSpacing: CGFloat = 12.0
        static let featuresListPadding: CGFloat = 16.0
        static let featuresListTopPadding: CGFloat = 12.0
        static let featuresListBorderCornerRadius: CGFloat = 8.0
    }
}

struct SaveLoginView_Previews: PreviewProvider {
    private struct MockManager: SaveAutofillLoginManagerProtocol {
        var hasSavedMatchingUsernameWithoutPassword: Bool { false }

        var username: String { "dax@duck.com" }
        var visiblePassword: String { "supersecurepasswordquack" }
        var isNewAccount: Bool { false }
        var accountDomain: String { "duck.com" }
        var isPasswordOnlyAccount: Bool { false }
        var hasOtherCredentialsOnSameDomain: Bool { false }
        var hasSavedMatchingPasswordWithoutUsername: Bool { false }
        var hasSavedMatchingUsername: Bool { false }
        
        static func saveCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, with factory: AutofillVaultFactory) throws -> Int64 { return 0 }
    }
    
    static var previews: some View {
        Group {
            let featureFlagger = AppDependencyProvider.shared.featureFlagger
            let viewModelNewUser = SaveLoginViewModel(credentialManager: MockManager(),
                                                      appSettings: AppDependencyProvider.shared.appSettings,
                                                      featureFlagger: featureFlagger,
                                                      layoutType: .newUser)
            let viewModelSaveLogin = SaveLoginViewModel(credentialManager: MockManager(),
                                                        appSettings: AppDependencyProvider.shared.appSettings,
                                                        featureFlagger: featureFlagger,
                                                        layoutType: .saveLogin)

            VStack {
                SaveLoginView(viewModel: viewModelNewUser)
                SaveLoginView(viewModel: viewModelSaveLogin)
            }.preferredColorScheme(.dark)
            
            VStack {
                SaveLoginView(viewModel: viewModelNewUser)
                SaveLoginView(viewModel: viewModelSaveLogin)
            }.preferredColorScheme(.light)
            
            VStack {
                let viewModelUpdatePassword = SaveLoginViewModel(credentialManager: MockManager(),
                                                                 appSettings: AppDependencyProvider.shared.appSettings,
                                                                 featureFlagger: featureFlagger,
                                                                 layoutType: .updatePassword)
                SaveLoginView(viewModel: viewModelUpdatePassword)
                
                let viewModelUpdateUsername = SaveLoginViewModel(credentialManager: MockManager(),
                                                                 appSettings: AppDependencyProvider.shared.appSettings,
                                                                 featureFlagger: featureFlagger,
                                                                 layoutType: .updateUsername)
                SaveLoginView(viewModel: viewModelUpdateUsername)
            }
            
            VStack {
                let viewModelAdditionalLogin = SaveLoginViewModel(credentialManager: MockManager(),
                                                                  appSettings: AppDependencyProvider.shared.appSettings,
                                                                  featureFlagger: featureFlagger,
                                                                  layoutType: .saveLogin)
                SaveLoginView(viewModel: viewModelAdditionalLogin)
                
                let viewModelSavePassword = SaveLoginViewModel(credentialManager: MockManager(),
                                                               appSettings: AppDependencyProvider.shared.appSettings,
                                                               featureFlagger: featureFlagger,
                                                               layoutType: .savePassword)
                SaveLoginView(viewModel: viewModelSavePassword)
            }
        }
    }
}
