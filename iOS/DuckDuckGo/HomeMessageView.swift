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
import DuckUI
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
            .modifier(HomeMessageButtonStyleModifier(actionStyle: buttonModel.actionStyle))
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

/// Routes home-message buttons through `DuckUI`'s canonical styles: `SecondaryFillButtonStyle`
/// for `.cancel` actions, `PrimaryButtonStyle` for everything else.
private struct HomeMessageButtonStyleModifier: ViewModifier {
    let actionStyle: HomeMessageButtonViewModel.ActionStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .cancel = actionStyle {
            content.buttonStyle(SecondaryFillButtonStyle(compact: true))
        } else {
            content.buttonStyle(PrimaryButtonStyle(compact: true))
        }
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
    static let background = Color(designSystemColor: .surface)
    static let updatedShadow = Color(designSystemColor: .shadowPrimary)
}

private enum Const {
    enum Radius {
        static let updatedShadow1: CGFloat = 12
        static let updatedShadow2: CGFloat = 48
        static let cornerLarge: CGFloat = 16
    }

    enum Padding {
        static let buttonVerticalInset: CGFloat = 8
    }

    enum Spacing {
        static let imageAndTitle: CGFloat = 8
    }

    enum Size {
        static let closeButtonWidth: CGFloat = 44
        static let imageMaxHeight: CGFloat = 48.0
    }

    enum Offset {
        static let updatedShadow1Vertical: CGFloat = 4
        static let updatedShadow2Vertical: CGFloat = 16
    }
}

// MARK: - Previews
//
// Two providers render the same five message variants under each `AppRebrand` state. Since
// `AppRebrand.isAppRebranded` is a process-wide closure, the most recently invoked provider's
// getter wins for any subsequent style lookup — switch between the previews one at a time
// rather than pinning both in the canvas.

private enum HomeMessagePreviewSamples {

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

    static func makeView(id: String, modelType: HomeSupportedMessageDisplayType) -> HomeMessageView {
        HomeMessageView(viewModel: HomeMessageViewModel(messageId: id,
                                                        modelType: modelType,
                                                        messageActionHandler: RemoteMessagingActionHandler(),
                                                        preloadedImage: nil,
                                                        loadRemoteImage: nil,
                                                        onDidClose: { _ in },
                                                        onDidAppear: {},
                                                        onAttachAdditionalParameters: { _, params in params }))
    }

    @ViewBuilder
    static var allMessages: some View {
        Group {
            makeView(id: "Small", modelType: small)
            makeView(id: "Critical", modelType: critical)
            makeView(id: "Big Single", modelType: bigSingle)
            makeView(id: "Big Two", modelType: bigTwo)
            makeView(id: "Promo", modelType: promo)
        }
        .frame(height: 200)
        .padding(.horizontal)
    }
}

struct HomeMessageView_LegacyPreviews: PreviewProvider {
    static var previews: some View {
        AppRebrand.isAppRebranded = { false }
        return HomeMessagePreviewSamples.allMessages
            .previewDisplayName("Legacy")
    }
}

struct HomeMessageView_RebrandedPreviews: PreviewProvider {
    static var previews: some View {
        AppRebrand.isAppRebranded = { true }
        return HomeMessagePreviewSamples.allMessages
            .previewDisplayName("Rebranded")
    }
}
