//
//  VPNUpsellPopover.swift
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

import AppKit
import Carbon.HIToolbox
import DesignResourcesKit
import Lottie
import Subscription
import SwiftUI
import SwiftUIExtensions

// MARK: - Constants

private enum Constants {
    static let popoverWidth: CGFloat = 320
    static let outerVerticalSpacing: CGFloat = 16
    static let innerVerticalSpacing: CGFloat = 28
    static let headerHorizontalPadding: CGFloat = 36
    static let titleAndSubtitleHorizontalPadding: CGFloat = 36
    static let titleAndSubtitleMaxWidth: CGFloat = 280
    static let titleAndSubtitleVerticalSpacing: CGFloat = 8
    static let featuresHorizontalPadding: CGFloat = 24
    static let featuresVerticalSpacing: CGFloat = 12
    static let actionButtonsTopPadding: CGFloat = 12
    static let topPadding: CGFloat = 28
    static let horizontalPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 24
    static let sparkleSize: CGSize = CGSize(width: 250, height: 100)
    static let privacyProSize: CGSize = CGSize(width: 256, height: 96)
    static let plusRowHorizontalSpacing: CGFloat = 12
    static let plusRowVerticalSpacing: CGFloat = 4
    static let actionButtonHorizontalSpacing: CGFloat = 8
    static let actionButtonHeight: CGFloat = 28
    static let horizontalLineHeight: CGFloat = 1
    static let horizontalLineCornerRadius: CGFloat = 2
    static let featureRowImageSize: CGSize = CGSize(width: 16, height: 16)
    static let featureRowImageTopPadding: CGFloat = 2
    static let featureRowSubtitleVerticalSpacing: CGFloat = 2
    static let featureRowHorizontalSpacing: CGFloat = 8
    static let featureRowImageFontSize: CGFloat = 12
}

// MARK: - View

struct VPNUpsellPopoverView: View {
    @ObservedObject private var viewModel: VPNUpsellPopoverViewModel

    init(viewModel: VPNUpsellPopoverViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: Constants.outerVerticalSpacing) {
            animatedHeader
                .padding(.horizontal, Constants.headerHorizontalPadding)

            VStack(spacing: Constants.innerVerticalSpacing) {
                titleAndSubtitle
                    .frame(width: Constants.titleAndSubtitleMaxWidth)
                    .padding(.horizontal, Constants.titleAndSubtitleHorizontalPadding)
                features
                    .padding(.horizontal, Constants.featuresHorizontalPadding)
            }

            actionButtons
                .padding(.top, Constants.actionButtonsTopPadding)
        }
        .frame(width: Constants.popoverWidth)
        .padding(.top, Constants.topPadding)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    private var animatedHeader: some View {
        ZStack {
            LottieView(animation: .named("sparkleloop_wide"))
                .playing(loopMode: .loop)
                .frame(width: Constants.sparkleSize.width, height: Constants.sparkleSize.height)
                .clipped()
            LottieView(animation: .named("privacypro_devices"))
                .playing(loopMode: .playOnce)
                .frame(width: Constants.privacyProSize.width, height: Constants.privacyProSize.height)
                .clipped()
            }
    }

    private var titleAndSubtitle: some View {
        VStack(spacing: Constants.titleAndSubtitleVerticalSpacing) {
            Text(UserText.vpnUpsellPopoverTitle)
                .font(.title2.weight(.semibold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            Text(viewModel.featureSet.plusFeaturesSubtitle)
                .font(.subheadline)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(spacing: Constants.featuresVerticalSpacing) {
            ForEach(viewModel.featureSet.core, id: \.title) { feature in
                FeatureRow(text: feature.title, subtitle: feature.subtitle)
            }
            HStack(spacing: Constants.plusRowHorizontalSpacing) {
                horizontalLine
                Text(UserText.vpnUpsellPopoverPlusFeaturesSectionTitle.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                horizontalLine
            }
            .padding(.vertical, Constants.plusRowVerticalSpacing)

            ForEach(viewModel.featureSet.plus, id: \.title) { feature in
                FeatureRow(text: feature.title, subtitle: feature.subtitle)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Constants.actionButtonHorizontalSpacing) {
            Button {
                viewModel.dismiss()
            } label: {
                Text(UserText.vpnUpsellPopoverNoThanksButton)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(StandardButtonStyle())

            Button {
                viewModel.showSubscriptionLandingPage()
            } label: {
                Text(viewModel.featureSet.mainCTATitle.capitalized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(DefaultActionButtonStyle(enabled: true, shouldBeFixedVertical: false))
        }
        .frame(height: Constants.actionButtonHeight)
    }

    private var horizontalLine: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(maxWidth: .infinity, minHeight: Constants.horizontalLineHeight, maxHeight: Constants.horizontalLineHeight)
            .background(Color(designSystemColor: .controlsFillPrimary))
            .cornerRadius(Constants.horizontalLineCornerRadius)
    }

}

// MARK: - Feature Row

private struct FeatureRow: View {
    let text: String
    let subtitle: String?

    init(text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: Constants.featureRowHorizontalSpacing) {
            Image(systemName: "checkmark")
                .font(.system(size: Constants.featureRowImageFontSize, weight: .medium))
                .foregroundColor(Color(designSystemColor: .icons))
                .frame(width: Constants.featureRowImageSize.width, height: Constants.featureRowImageSize.height)
                .padding(.top, Constants.featureRowImageTopPadding)

            VStack(alignment: .leading, spacing: Constants.featureRowSubtitleVerticalSpacing) {
                Text(text)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NSPopover

final class VPNUpsellPopover: NSPopover {
    init(viewController: NSHostingController<some View>) {
        super.init()

        behavior = .semitransient
        contentViewController = viewController
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("VPNUpsellPopover: Bad initializer")
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            performClose(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
