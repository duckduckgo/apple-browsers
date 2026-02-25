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

        // Part of experiment "iOS: A/B test autofill onboarding"
        // https://app.asana.com/1/137249556945/project/72649045549333/task/1208707884599795
        case newUserVariant1
        case newUserVariant2
        case newUserVariant3
        
        var isNewUserVariant: Bool {
            switch self {
            case .newUser, .newUserVariant1, .newUserVariant2, .newUserVariant3:
                return true
            default:
                return false
            }
        }
    }
    @State var frame: CGSize = .zero
    @ObservedObject var viewModel: SaveLoginViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var orientation = UIDevice.current.orientation

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
        DispatchQueue.main.async { self.frame = geometry.size }

        return ZStack {
            AutofillViews.CloseButtonHeader(action: viewModel.cancelButtonPressed)
                .offset(x: horizontalPadding)
                .zIndex(1)

            innerContent
                .padding([.bottom], Const.Size.bodyBottomPadding)
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
            // Control layout
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

        case .newUserVariant1:
            // Design #3
            VStack {
                Spacer(minLength: Const.Size.topPadding)
                experimentHeaderView
                    .padding(.bottom, 4)
                AutofillViews.Headline(title: UserText.autofillSaveLoginTitleNewUser)
                    .padding(.bottom, 4)
                AutofillViews.SecureDescription(text: UserText.autofillSaveLoginSecurityMessage)
                Spacer(minLength: Const.Size.contentSpacing)
                featuresView().padding([.bottom], Const.Size.featuresListPadding)
                onboardingCtaView()
            }

        case .newUserVariant2:
            // Design #4
            VStack {
                Spacer(minLength: Const.Size.topPadding)
                experimentHeaderView
                    .padding(.bottom, 4)
                AutofillViews.Headline(title: UserText.autofillSaveLoginTitleNewUser)
                Spacer(minLength: Const.Size.headlineToContentSpacing)
                AutofillViews.SecureDescription(text: UserText.autofillSaveLoginSecurityMessage, showIcon: false)
                Spacer(minLength: Const.Size.contentSpacing)
                onboardingCtaView()
            }

        case .newUserVariant3:
            // Design #7
            VStack(alignment: .leading) {
                Spacer(minLength: Const.Size.topPadding)
                experimentHeaderView
                Spacer(minLength: Const.Size.contentSpacing)
                variant3TitleView
                onboardingCtaView(image: Image(uiImage: DesignSystemImages.Glyphs.Size24.shieldCheckSolid))
                VStack(alignment: .center) {
                    AutofillViews.SecureDescription(text: UserText.autofillSaveLoginSecurityMessage, showIcon: false)
                }
                .frame(maxWidth: .infinity)
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

    private var experimentHeaderView: some View {
        Image(.passwordsDDG96X96)
            .resizable()
            .frame(width: 96, height: 96)
    }

    // MARK: - Variant 3 Views

    private func variant3TitleAttributedString(fontSize: CGFloat) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = fontSize
        paragraphStyle.maximumLineHeight = fontSize

        let result = NSMutableAttributedString()

        result.append(NSAttributedString(string: NotLocalizedString("autofill.save-login.variant3.title", value: "Store\npasswords\nsecurely\n", comment: "Title text on the variant 3 save login prompt"), attributes: [
            .font: font,
            .foregroundColor: UIColor(designSystemColor: .textPrimary),
            .paragraphStyle: paragraphStyle
        ]))

        result.append(NSAttributedString(string: NotLocalizedString("autofill.save-login.variant3.subtitle", value: "with DuckDuckGo", comment: "Subtitle on the variant 3 save login prompt, displayed below the title"), attributes: [
            .font: font,
            .foregroundColor: UIColor(designSystemColor: .textTertiary),
            .paragraphStyle: paragraphStyle
        ]))

        return result
    }

    /// Calculate the font size based on the content width and the text width in the original design.
    /// The font size will be scaled down if the text width is less than the original design width.
    private var variant3FontSize: CGFloat {
        let contentWidth = frame.width - (horizontalPadding * 2)
        let textWidth = contentWidth - (Const.Size.variant3TitleHorizontalPadding * 2)
        guard textWidth > 0 else { return Const.Size.variant3TitleFontSize }
        let scaled = Const.Size.variant3TitleFontSize * (textWidth / Const.Size.variant3MaximumTextWidth)
        return min(scaled, Const.Size.variant3TitleFontSize)
    }

    private var variant3TitleView: some View {
        AttributedText(attributedString: variant3TitleAttributedString(fontSize: variant3FontSize))
            .padding(.horizontal, Const.Size.variant3TitleHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.bottom], Const.Size.featuresListPadding)
    }

    // MARK: - CTA Views

    /// CTA buttons for onboarding flows
    ///
    private func onboardingCtaView(image: Image? = nil) -> some View {
        VStack(spacing: Const.Size.ctaVerticalSpacing) {
            AutofillViews.PrimaryButton(title: UserText.autofillSavePasswordSaveCTA,
                                        image: image,
                                        action: viewModel.save)
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
        static let variant3TitleFontSize: CGFloat = 40.0
        static let variant3MaximumTextWidth: CGFloat = 338.0
        static let variant3TitleHorizontalPadding: CGFloat = 8.0
    }
}

/// A view that displays an attributed string.
/// Required because SwiftUI's attributed string support is limited.
private struct AttributedText: UIViewRepresentable {
    let attributedString: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedString
        label.preferredMaxLayoutWidth = label.bounds.width
        label.invalidateIntrinsicContentSize()
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
