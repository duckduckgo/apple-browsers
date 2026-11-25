//
//  RMFSheetView+Previews.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

#if os(iOS) && DEBUG

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import PreviewSnapshots

/// Sample sheets matching the Figma promo examples (`RMF Sheet` 6:896, `RMF Sheet / iPad` 54:9391,
/// and the promo frames 10:566 and 53:4824). Copy is sample copy, not localised.
enum RMFSheetPreviewExample: CaseIterable {
    case template
    case cookie
    case whatsNew
    case winBack
}

struct RMFSheetPreviewState {
    let example: RMFSheetPreviewExample
    let layout: RMFSheetLayout
    var largeText = false
}

struct RMFSheetView_Previews: PreviewProvider {

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<RMFSheetPreviewState>(
        configurations: [
            .init(name: "Phone - Template", state: .init(example: .template, layout: .phone)),
            .init(name: "Phone Fullscreen - Template", state: .init(example: .template, layout: .phoneFullscreen)),
            .init(name: "Phone - Win-back", state: .init(example: .winBack, layout: .phone)),
            .init(name: "Phone Fullscreen - Cookie", state: .init(example: .cookie, layout: .phoneFullscreen)),
            .init(name: "Phone - Whats New", state: .init(example: .whatsNew, layout: .phone)),
            .init(name: "iPad Regular - Cookie", state: .init(example: .cookie, layout: .padRegular)),
            .init(name: "iPad Compact - Cookie", state: .init(example: .cookie, layout: .padCompact)),
            .init(name: "iPad Regular - Whats New", state: .init(example: .whatsNew, layout: .padRegular)),
            .init(name: "Phone Fullscreen - Cookie AX5", state: .init(example: .cookie, layout: .phoneFullscreen, largeText: true)),
            .init(name: "Phone - Whats New AX5", state: .init(example: .whatsNew, layout: .phone, largeText: true)),
        ],
        configure: { state in
            RMFSheetPreviewFrame(layout: state.layout, largeText: state.largeText) {
                RMFSheetPreviewSheet(example: state.example)
            }
        }
    )
}

/// One of the sample sheets.
struct RMFSheetPreviewSheet: View {
    let example: RMFSheetPreviewExample

    var body: some View {
        switch example {
        case .template:
            RMFSheetView(title: "Title goes here",
                         bodyText: "Body text explains the benefit in one or two short sentences.",
                         primaryAction: RMFSheetAction(title: "Primary action") {},
                         secondaryAction: RMFSheetAction(title: "Not now") {},
                         closeAccessibilityLabel: "Close",
                         fullscreen: true) {
                pictogram(DesignSystemImages.Color.Size96.announcement)
            }
        case .cookie:
            RMFSheetView(title: "Tired of cookie pop-ups that don't let you opt out?",
                         bodyText: "We can save you a click and accept these cookies for you.",
                         footnote: "You can always adjust later in Settings › Cookie Pop-Up Protection.",
                         primaryAction: RMFSheetAction(title: "Confirm") {},
                         dismissable: false,
                         closeAccessibilityLabel: "Close",
                         fullscreen: true) {
                pictogram(DesignSystemImages.Color.Size96.cookieCheckFeature)
            } content: {
                SheetChoiceList(viewModel: SheetChoiceListViewModel(options: [
                    SheetChoiceOption(title: "Accept cookies that can't be rejected"),
                    SheetChoiceOption(title: "I'll keep accepting them myself"),
                ]))
            }
        case .whatsNew:
            RMFSheetView(title: "What's New",
                         primaryAction: RMFSheetAction(title: "Got It") {},
                         closeAccessibilityLabel: "Close") {
                pictogram(DesignSystemImages.Color.Size96.duckDuckGo)
            } content: {
                SheetCardList(items: [
                    SheetCardListItem(icon: .image(Image(uiImage: DesignSystemImages.Color.Size96.duckAI)),
                                      title: "Sync Duck.ai Chats Across Devices",
                                      text: "Sync your chats across desktop and mobile by visiting Duck.ai Settings > Sync & Backup."),
                    SheetCardListItem(icon: .image(Image(uiImage: DesignSystemImages.Color.Size96.fire)),
                                      title: "Browse With Fire Tabs",
                                      text: "Use Fire Tabs to isolate your browsing from normal tabs and browse without saving local history."),
                    SheetCardListItem(icon: .image(Image(uiImage: DesignSystemImages.Color.Size96.duckAISubscription)),
                                      title: "Explore More Subscription Options",
                                      text: "Pick from two plans: Plus (for all four protections) or Pro (for more powerful AI functionality)."),
                ]) { _ in }
            }
        case .winBack:
            RMFSheetView(eyebrowText: "Limited time only",
                         title: "We want you back! Get 25% off.",
                         bodyText: "Stay protected with our VPN, private AI, and more. Resubscribe today and save 25%.",
                         primaryAction: RMFSheetAction(title: "See Offer") {},
                         secondaryAction: RMFSheetAction(title: "Not Now") {},
                         closeAccessibilityLabel: "Close") {
                pictogram(DesignSystemImages.Color.Size96.duckAISubscription)
            }
        }
    }

    private func pictogram(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: RMFSheetMetrics(layout: .phone).pictogramSize,
                   height: RMFSheetMetrics(layout: .phone).pictogramSize)
    }
}

/// Renders a sheet at its Figma reference size with the sheet chrome a presenter would add.
struct RMFSheetPreviewFrame<Sheet: View>: View {
    let layout: RMFSheetLayout
    var largeText = false
    @ViewBuilder let sheet: () -> Sheet

    var body: some View {
        let metrics = layout.metrics
        sheet()
            .rmfSheetLayout(layout)
            .frame(width: metrics.referenceWidth, height: height)
            // At large text, cap the content-height sheet at a phone's height so it has to scroll.
            .frame(maxHeight: largeText && height == nil ? Self.phoneHeight : nil)
            .clipShape(RoundedRectangle(cornerRadius: metrics.sheetCornerRadius, style: .continuous))
            .dynamicTypeSize(largeText ? .accessibility5 : .large)
            .padding(16)
            .background(Color(designSystemColor: .background))
    }

    private static var phoneHeight: CGFloat { 844 }

    private var height: CGFloat? {
        switch layout {
        case .phone, .padRegular: nil
        case .phoneFullscreen: 790
        case .padCompact: 1000
        }
    }
}

#Preview("Cookie - Phone Fullscreen Dark") {
    RMFSheetPreviewFrame(layout: .phoneFullscreen) {
        RMFSheetPreviewSheet(example: .cookie)
    }
    .preferredColorScheme(.dark)
}

#Preview("Whats New - Phone Dark") {
    RMFSheetPreviewFrame(layout: .phone) {
        RMFSheetPreviewSheet(example: .whatsNew)
    }
    .preferredColorScheme(.dark)
}

#Preview("Template - Phone Fullscreen Off/On") {
    HStack(alignment: .bottom, spacing: 0) {
        RMFSheetPreviewFrame(layout: .phone) {
            RMFSheetPreviewSheet(example: .template)
        }
        RMFSheetPreviewFrame(layout: .phoneFullscreen) {
            RMFSheetPreviewSheet(example: .template)
        }
    }
}

#Preview("Cookie - iPad Regular/Compact Dark") {
    HStack(alignment: .top, spacing: 0) {
        RMFSheetPreviewFrame(layout: .padRegular) {
            RMFSheetPreviewSheet(example: .cookie)
        }
        RMFSheetPreviewFrame(layout: .padCompact) {
            RMFSheetPreviewSheet(example: .cookie)
        }
    }
    .preferredColorScheme(.dark)
}

#endif
