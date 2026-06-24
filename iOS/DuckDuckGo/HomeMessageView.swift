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
import MetricBuilder
import RemoteMessaging
import Core

struct HomeMessageView: View {

    let viewModel: HomeMessageViewModel

    @State var activityItem: TitleValueShareItem?
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if case .promoSingleAction = viewModel.modelType {
                        title
                            .daxTitle3()
                            .padding(.top, 16)
                        image
                            .padding(.top, Const.Spacing.imageAndTitle)
                    } else {
                        image
                        title
                            .daxHeadline()
                            .padding(.top, Const.Spacing.imageAndTitle)
                    }

                    subtitle
                        .padding(.top, Const.Spacing.titleAndSubtitle)
                }
                .padding(.top, 16)
                .padding(.horizontal, 40)

                // Button-less messages (small/medium) need their own bottom inset
                .padding(.bottom, viewModel.buttons.isEmpty ? Const.Spacing.contentBottom : 0)

                if !viewModel.buttons.isEmpty {
                    HStack {
                        buttons
                    }
                    .padding(.top, Const.Spacing.subtitleAndButtons)
                    .padding([.horizontal, .bottom], AppRebrand.isAppRebranded() ? ButtonStackMetrics.containerPadding : 16)
                }
            }
            .multilineTextAlignment(.center)

            closeButton
                .padding(ContainerMetrics.closeButtonPadding - CloseButtonStyle.Constant.padding)
        }
        .background(RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
            .fill(Color.background)
            .shadow(color: Color.updatedShadow, radius: Const.Radius.updatedShadow1, x: 0, y: Const.Offset.updatedShadow1Vertical)
            .shadow(color: Color.updatedShadow, radius: Const.Radius.updatedShadow2, x: 0, y: Const.Offset.updatedShadow2Vertical)
        )
        .onAppear {
            viewModel.onDidAppear()
        }
    }

    private var closeButton: some View {
        Button {
            Task {
                await viewModel.onDidClose(.close)
            }
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
        }
        .buttonStyle(CloseButtonStyle())
    }
    
    @ViewBuilder
    private var image: some View {
        if let displayImage = loadedImage ?? viewModel.preloadedImage {
            Image(uiImage: displayImage)
                .resizable()
                .scaledToFit()
                .modifier(PictogramSize(legacyMaxHeight: Const.Size.imageMaxHeight))
        } else if let placeholderName = viewModel.image {
            Image(rebrandable: placeholderName)
                .scaledToFit()
                .modifier(PictogramSize(legacyMaxHeight: nil))
                .task {
                    loadedImage = await viewModel.loadRemoteImage?()
                }
        }
    }

    private var title: some View {
        Text(viewModel.title)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
   }

    private var subtitleColor: Color? {
        AppRebrand.isAppRebranded() ? Color(designSystemColor: .textSecondary) : nil
    }

    @ViewBuilder
    private func subtitleFont(_ text: Text) -> some View {
        if AppRebrand.isAppRebranded() {
            text.daxSubheadRegular()
        } else {
            text.daxBodyRegular()
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let attributed = try? AttributedString(markdown: viewModel.subtitle) {
            subtitleFont(Text(attributed))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(subtitleColor)
        } else {
            subtitleFont(Text(viewModel.subtitle))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(subtitleColor)
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
                    buttonTitleView(for: buttonModel.title)
                }
            }
            .modifier(HomeMessageButtonStyleModifier(actionStyle: buttonModel.actionStyle))
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

    @ViewBuilder
    private func buttonTitleView(for title: String) -> some View {
        if AppRebrand.isAppRebranded() {
            Text(title)
        } else {
            Text(title)
                .daxButton()
        }
    }
}

private struct HomeMessageButtonStyleModifier: ViewModifier {
    let actionStyle: HomeMessageButtonViewModel.ActionStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .cancel = actionStyle {
            content.buttonStyle(SecondaryFillButtonStyle(compact: true))
        } else if AppRebrand.isAppRebranded() {
            content.buttonStyle(BrandButtonStyle(compact: true))
        } else {
            content.buttonStyle(PrimaryButtonStyle(compact: true))
        }
    }
}

private struct PictogramSize: ViewModifier {
    let legacyMaxHeight: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppRebrand.isAppRebranded() {
            content.frame(width: Const.Size.rebrandedPictogram, height: Const.Size.rebrandedPictogram)
        } else if let legacyMaxHeight {
            content.frame(maxHeight: legacyMaxHeight)
        } else {
            content
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
    }

    enum Spacing {
        static let imageAndTitle: CGFloat = 8
        static let titleAndSubtitle: CGFloat = 2
        static let subtitleAndButtons: CGFloat = 24
        static let contentBottom: CGFloat = 24
    }

    enum Size {
        static let imageMaxHeight: CGFloat = 48.0
        static let rebrandedPictogram: CGFloat = 96
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
        ScrollView {
            VStack {
                makeView(id: "Small", modelType: small)
                makeView(id: "Critical", modelType: critical)
                makeView(id: "Big Single", modelType: bigSingle)
                makeView(id: "Big Two", modelType: bigTwo)
                makeView(id: "Promo", modelType: promo)
            }
            .padding(.horizontal)
        }
        .background(Color.gray)
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
