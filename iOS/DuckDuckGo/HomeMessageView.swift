//
//  HomeMessageView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import RemoteMessaging
import Core

struct HomeMessageView: View {

    let viewModel: HomeMessageViewModel

    @State var activityItem: TitleValueShareItem?
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Group {
                    if case .promoSingleAction = viewModel.modelType {
                        title
                            .daxTitle3()
                            .padding(.top, 16)
                        image
                    } else {
                        image
                        title
                            .daxHeadline()
                    }

                    subtitle
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                HStack {
                    buttons
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical)
            .padding(.horizontal, 8)

            closeButtonHeader
                .alignmentGuide(.top) { dimension in
                    dimension[.top]
                }
        }
        .background(RoundedRectangle(cornerRadius: Const.Radius.cornerLarge)
            .fill(Color.background)
            .shadow(color: Color.updatedShadow, radius: Const.Radius.updatedShadow1, x: 0, y: Const.Offset.updatedShadow1Vertical)
            .shadow(color: Color.updatedShadow, radius: Const.Radius.updatedShadow2, x: 0, y: Const.Offset.updatedShadow2Vertical)
        )
        .onAppear {
            viewModel.onDidAppear()
        }
    }

    private var closeButtonHeader: some View {
        VStack {
            HStack {
                Spacer()
                closeButton
                    .padding(0)
            }
        }
    }
    
    private var closeButton: some View {
        Button {
            Task {
                await viewModel.onDidClose(.close)
            }
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                .foregroundColor(.primary)
        }
        .frame(width: Const.Size.closeButtonWidth, height: Const.Size.closeButtonWidth)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var image: some View {
        if let displayImage = loadedImage ?? viewModel.preloadedImage {
            Image(uiImage: displayImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: Const.Size.imageMaxHeight)
        } else if let placeholderName = viewModel.image {
            Image(placeholderName)
                    .scaledToFit()
                .task {
                    loadedImage = await viewModel.loadRemoteImage?()
            }
        }
    }

    private var title: some View {
        Text(viewModel.title)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Const.Spacing.imageAndTitle)
            .frame(maxWidth: .infinity)
   }

    @ViewBuilder
    private var subtitle: some View {
        if let attributed = try? AttributedString(markdown: viewModel.subtitle) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
                .daxBodyRegular()
        } else {
            Text(viewModel.subtitle)
                .fixedSize(horizontal: false, vertical: true)
                .daxBodyRegular()
        }
    }

    private var buttons: some View {
        ForEach(viewModel.buttons, id: \.title) { buttonModel in
            Button {
                Task { @MainActor in
                    await buttonModel.action(self)
                }
            } label: {
                HStack {
                    if case .share = buttonModel.actionStyle {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.shareApple)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    Text(buttonModel.title)
                        .daxButton()
                }
            }
            .buttonStyle(HomeMessageButtonStyle(buttonModel: buttonModel))
            .padding([.bottom], Const.Padding.buttonVerticalInset)
            .sheet(item: $activityItem) { activityItem in
                ActivityViewController(activityItems: [activityItem.item]) { _, result, _, _ in
                    var additionalParameters = [
                        PixelParameters.message: "\(viewModel.messageId)",
                        PixelParameters.sheetResult: "\(result)"
                    ]
                    additionalParameters = viewModel.onAttachAdditionalParameters?(.messageID(viewModel.messageId), additionalParameters) ?? additionalParameters
                    Pixel.fire(pixel: .remoteMessageSheet, withAdditionalParameters: additionalParameters)
                }
                .modifier(ActivityViewPresentationModifier())
            }

        }
    }
}

private struct HomeMessageButtonStyle: ButtonStyle {

    let buttonModel: HomeMessageButtonViewModel

    var foregroundColor: Color {
        if case .cancel = buttonModel.actionStyle {
            return .cancelButtonForeground
        }

        return .primaryButtonText
    }

    var backgroundColor: Color {
        if case .cancel = buttonModel.actionStyle {
            return .cancelButtonBackground
        }

        return .button
    }

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Const.Padding.buttonHorizontal)
            .padding(.vertical, Const.Padding.buttonVertical)
            .frame(height: Const.Size.buttonHeight)
            .foregroundColor(configuration.isPressed ? foregroundColor.opacity(0.5) : foregroundColor)
            .background(backgroundColor)
            .cornerRadius(Const.Radius.corner)
    }
}

struct ActivityViewPresentationModifier: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium])
        } else {
            content
        }
    }

}

extension HomeMessageView: RemoteMessagingPresenter {

    @MainActor
    func presentActivitySheet(value: String, title: String?) async {
        activityItem = TitleValueShareItem(value: value, title: title)
    }

    @MainActor
    func presentEmbeddedWebView(url: URL) async {
        assertionFailure("Action defined as part of https://app.asana.com/1/137249556945/project/1206329551987282/task/1211135151986316. Not implemented yet for Home Messages")
    }

}

private extension Color {
    static let button = Color(designSystemColor: .buttonsPrimaryDefault)
    static let primaryButtonText = Color(designSystemColor: .buttonsPrimaryText)
    static let cancelButtonBackground = Color(designSystemColor: .buttonsSecondaryFillDefault)
    static let cancelButtonForeground = Color(designSystemColor: .buttonsSecondaryFillText)
    static let background = Color(designSystemColor: .surface)
    static let shadow = Color.shade(0.1)
    static let updatedShadow = Color(designSystemColor: .shadowPrimary)
}

private extension Image {
    static let dismiss = Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
}

private enum Const {
    enum Font {
        static let topText = UIFont.boldAppFont(ofSize: 13)
        static let title = UIFont.boldAppFont(ofSize: 17)
        static let subtitle = UIFont.appFont(ofSize: 15)
        static let button = UIFont.boldAppFont(ofSize: 15)
    }
    
    enum Radius {
        static let shadow: CGFloat = 3
        static let updatedShadow1: CGFloat = 12
        static let updatedShadow2: CGFloat = 48
        static let corner: CGFloat = 8
        static let cornerLarge: CGFloat = 16
    }
    
    enum Padding {
        static let buttonHorizontal: CGFloat = 16
        static let buttonVertical: CGFloat = 9
        static let buttonVerticalInset: CGFloat = 8
        static let textHorizontalInset: CGFloat = 30
    }
    
    enum Spacing {
        static let imageAndTitle: CGFloat = 8
        static let titleAndSubtitle: CGFloat = 4
        static let subtitleAndButtons: CGFloat = 6
        static let line: CGFloat = 4
    }
    
    enum Size {
        static let closeButtonWidth: CGFloat = 44
        static let buttonHeight: CGFloat = 40
        static let imageMaxHeight: CGFloat = 48.0
    }
    
    enum Offset {
        static let shadowVertical: CGFloat = 2
        static let updatedShadow1Vertical: CGFloat = 4
        static let updatedShadow2Vertical: CGFloat = 16
    }
}

struct HomeMessageView_Previews: PreviewProvider {

    static let small: HomeSupportedMessageDisplayType =
        .small(titleText: "Small", descriptionText: "Description")

    static let critical: HomeSupportedMessageDisplayType =
        .medium(titleText: "Critical",
                descriptionText: "Description text",
                placeholder: .criticalUpdate,
                imageUrl: nil)

    static let bigSingle: HomeSupportedMessageDisplayType =
        .bigSingleAction(titleText: "Big Single",
                         descriptionText: "This is a description",
                         placeholder: .ddgAnnounce,
                         imageUrl: nil,
                         primaryActionText: "Primary",
                         primaryAction: .dismiss)

    static let bigTwo: HomeSupportedMessageDisplayType =
        .bigTwoAction(titleText: "Big Two",
                      descriptionText: "This is a <b>big</b> two style",
                      placeholder: .macComputer,
                      imageUrl: nil,
                      primaryActionText: "App Store",
                      primaryAction: .appStore,
                      secondaryActionText: "Dismiss",
                      secondaryAction: .dismiss)

    static let promo: HomeSupportedMessageDisplayType =
        .promoSingleAction(titleText: "Promotional",
                           descriptionText: "Description <b>with bold</b> to make a statement.",
                           placeholder: .newForMacAndWindows,
                           imageUrl: nil,
                           actionText: "Share",
                           action: .share(value: "value", title: "title"))

    static var previews: some View {
        Group {
            HomeMessageView(viewModel: HomeMessageViewModel(messageId: "Small",
                                                            modelType: small,
                                                            messageActionHandler: RemoteMessagingActionHandler(),
                                                            preloadedImage: nil,
                                                            loadRemoteImage: nil,
                                                            onDidClose: { _ in }, onDidAppear: {}, onAttachAdditionalParameters: { _, params in params }))

            HomeMessageView(viewModel: HomeMessageViewModel(messageId: "Critical",
                                                            modelType: critical,
                                                            messageActionHandler: RemoteMessagingActionHandler(),
                                                            preloadedImage: nil,
                                                            loadRemoteImage: nil,
                                                            onDidClose: { _ in }, onDidAppear: {}, onAttachAdditionalParameters: { _, params in params }))

            HomeMessageView(viewModel: HomeMessageViewModel(messageId: "Big Single",
                                                            modelType: bigSingle,
                                                            messageActionHandler: RemoteMessagingActionHandler(),
                                                            preloadedImage: nil,
                                                            loadRemoteImage: nil,
                                                            onDidClose: { _ in }, onDidAppear: {}, onAttachAdditionalParameters: { _, params in params }))

            HomeMessageView(viewModel: HomeMessageViewModel(messageId: "Big Two",
                                                            modelType: bigTwo,
                                                            messageActionHandler: RemoteMessagingActionHandler(),
                                                            preloadedImage: nil,
                                                            loadRemoteImage: nil,
                                                            onDidClose: { _ in }, onDidAppear: {}, onAttachAdditionalParameters: { _, params in params }))

            HomeMessageView(viewModel: HomeMessageViewModel(messageId: "Promo",
                                                            modelType: promo,
                                                            messageActionHandler: RemoteMessagingActionHandler(),
                                                            preloadedImage: nil,
                                                            loadRemoteImage: nil,
                                                            onDidClose: { _ in }, onDidAppear: {}, onAttachAdditionalParameters: { _, params in params }))
        }
        .frame(height: 200)
        .padding(.horizontal)

    }

    struct PreviewNavigator: MessageNavigator {
        func navigateTo(_ target: RemoteMessaging.NavigationTarget, presentationStyle: PresentationContext.Style) {
            // no-op
        }
    }
}
