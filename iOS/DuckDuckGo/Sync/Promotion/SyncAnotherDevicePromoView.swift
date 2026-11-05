//
//  SyncAnotherDevicePromoView.swift
//  DuckDuckGo
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

#if DEBUG
import PreviewSnapshots
#endif

struct SyncAnotherDevicePromoView: View {

    private enum Metrics {
        static let closeButtonInset: CGFloat = 12
        static let closeButtonReserve: CGFloat = 52
        static let imageSize: CGFloat = 56
        static let buttonSpacing: CGFloat = 8
    }

    let title: String
    var connectTitle: String = UserText.syncPromoAnotherDeviceConnectAction
    let syncAction: () -> Void
    let getDesktopAppAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Image("RemoteMessageNewForMacAndWindows")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .daxHeadline()
                            .foregroundColor(Color(designSystemColor: .textPrimary))

                        Text(UserText.syncPromoAnotherDeviceMessage)
                            .daxSubheadRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
                .padding(.top, 8)
                .padding(.leading, 16)
                .padding(.trailing, Metrics.closeButtonReserve)

                buttons
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
            }
            .padding(.top, 12)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.bottom, 16)

            Button(action: dismissAction) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
            }
            .buttonStyle(CloseButtonStyle())
            .padding(Metrics.closeButtonInset - CloseButtonStyle.Constant.padding)
            .accessibilityLabel(UserText.syncPromoCloseAccessibilityLabel)
        }
        .background(
            RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
                .foregroundColor(Color(designSystemColor: .surfaceSecondary))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var buttons: some View {
        if #available(iOS 16.0, *) {
            PromoButtonsLayout(spacing: Metrics.buttonSpacing) {
                buttonViews(singleLine: false)
            }
        } else {
            HStack(spacing: Metrics.buttonSpacing) {
                buttonViews(singleLine: true)
            }
        }
    }

    @ViewBuilder
    private func buttonViews(singleLine: Bool) -> some View {
        Button(action: getDesktopAppAction) {
            buttonText(UserText.syncPromoAnotherDeviceGetDesktopAppAction, singleLine: singleLine)
        }
        .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: true))

        Button(action: syncAction) {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.qrScan)
                    .accessibilityHidden(true)
                buttonText(connectTitle, singleLine: singleLine)
            }
        }
        .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: true))
    }

    private func buttonText(_ title: String, singleLine: Bool) -> some View {
        Text(title)
            .lineLimit(singleLine ? 1 : nil)
            .minimumScaleFactor(singleLine ? 0.8 : 1)
    }
}

/// Places the buttons side by side in equal-width columns when each whole button fits its column on one line.
/// Otherwise stacks them full width with the last, primary, button on top, letting long labels wrap.
@available(iOS 16.0, *)
private struct PromoButtonsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let width = proposal.width ?? (idealWidths.max() ?? 0) * CGFloat(subviews.count) + totalSpacing(subviews)
        return CGSize(width: width, height: frames(in: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(in: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func totalSpacing(_ subviews: Subviews) -> CGFloat {
        CGFloat(max(subviews.count - 1, 0)) * spacing
    }

    private func frames(in width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard !subviews.isEmpty else { return [] }

        let columnWidth = (width - totalSpacing(subviews)) / CGFloat(subviews.count)
        if subviews.allSatisfy({ $0.sizeThatFits(.unspecified).width <= columnWidth }) {
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
            return subviews.indices.map { CGRect(x: CGFloat($0) * (columnWidth + spacing), y: 0, width: columnWidth, height: height) }
        }

        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        for index in subviews.indices.reversed() {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            frames[index] = CGRect(x: 0, y: y, width: width, height: height)
            y += height + spacing
        }
        return frames
    }
}

#if DEBUG
struct SyncAnotherDevicePromoView_Previews: PreviewProvider {

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots(configurations: [
        .init(name: "Bookmarks", state: (title: UserText.syncPromoBookmarksAnotherDeviceTitle, connectTitle: UserText.syncPromoAnotherDeviceConnectAction)),
        .init(name: "Passwords", state: (title: UserText.syncPromoPasswordsAnotherDeviceTitle, connectTitle: UserText.syncPromoAnotherDeviceConnectAction)),
        .init(name: "Long Action", state: (title: UserText.syncPromoPasswordsAnotherDeviceTitle, connectTitle: "Passwörter mit einem anderen Gerät synchronisieren und sichern"))
    ]) { state in
        SyncAnotherDevicePromoView(title: state.title, connectTitle: state.connectTitle, syncAction: {}, getDesktopAppAction: {}, dismissAction: {})
            .background(Color(designSystemColor: .background))
    }
}
#endif
