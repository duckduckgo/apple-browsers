//
//  SyncPromoView.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SwiftUIExtensions
import PixelKit

struct SyncPromoView: View {

    enum Layout {
        case compact
        case horizontal
        case vertical(topPadding: CGFloat)
        case auto(verticalLayoutTopPadding: CGFloat)

        static let auto = Self.auto(verticalLayoutTopPadding: 70)
        static let vertical = Self.vertical(topPadding: 70)
    }

    @State private var isHovering = false
    @State private var width: CGFloat = 0

    let viewModel: SyncPromoViewModel
    var layout: Layout = .compact
    var autoLayoutWidthThreshold: CGFloat = 400

    var body: some View {
        Group {
            switch layout {
            case .compact:
                compactLayoutView
            case .horizontal,
                 .auto where width >= autoLayoutWidthThreshold:
                horizontalLayoutView
            case .vertical(let topPadding), .auto(let topPadding):
                verticalLayoutView(topPadding: topPadding)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear.onAppear {
                    PixelKit.fire(SyncPromoPixelKitEvent.syncPromoDisplayed.withoutMacPrefix, withAdditionalParameters: ["source": viewModel.touchpointType.rawValue])
                    width = geometry.size.width
                }
                .onChange(of: geometry.size.width) { newWidth in
                    width = newWidth
                }
            }
        )
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            VStack {
                CloseButton(icon: .close, size: 16) {
                    dismissAction()
                }
                .padding(6)

                Spacer()
            }
        }
    }

    private var backgroundRectangle: some View {
        RoundedRectangle(cornerRadius: 8)
            .foregroundColor(isHovering ? Color.black.opacity(0.06) : Color.blackWhite3)
    }

    private var image: some View {
        Image(viewModel.image)
            .resizable()
            .frame(width: 48, height: 48)
    }

    private var title: some View {
        Text(viewModel.title)
            .font(.system(size: isVerticalLayout ? 15 : 13).bold())
            .multilineTextAlignment(isVerticalLayout ? .center : .leading)
            .multilineText()
    }

    private var subtitle: some View {
        Text(viewModel.subtitle)
            .multilineTextAlignment(isVerticalLayout ? .center : .leading)
            .multilineText()
    }

    private var isVerticalLayout: Bool {
        switch layout {
        case .vertical:
            return true
        case .horizontal, .compact:
            return false
        case .auto:
            return width < autoLayoutWidthThreshold
        }
    }

    private var compactLayoutView: some View {
        ZStack {
            backgroundRectangle

            HStack(alignment: .top) {
                image
                    .padding(.top, 14)

                VStack(alignment: .leading) {

                    title

                    subtitle
                        .padding(.top, 1)
                        .padding(.bottom, 6)

                    HStack {
                        Button(viewModel.secondaryButtonTitle) {
                            dismissAction()
                        }
                        .buttonStyle(DismissActionButtonStyle())

                        Button(viewModel.primaryButtonTitle) {
                            primaryAction()
                        }
                        .buttonStyle(DefaultActionButtonStyle(enabled: true))
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 14)
                .padding(.trailing, 40)
            }
            .padding(.leading, 8)
        }
    }

    private var horizontalLayoutView: some View {
        ZStack {
            backgroundRectangle

            HStack(alignment: .center) {
                image

                VStack(alignment: .leading) {

                    title

                    subtitle
                        .padding(.bottom, 2)
                }

                Spacer()

                Button(viewModel.primaryButtonTitle) {
                    primaryAction()
                }
                .buttonStyle(DismissActionButtonStyle())
                .padding(.trailing, 32)
            }
            .padding(.leading, 8)
            .padding(.vertical, 8)

            closeButton
        }
        .onHover { isHovering in
            self.isHovering = isHovering
        }
    }

    private func verticalLayoutView(topPadding: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 16) {

            Image(.syncStart128)
                .resizable()
                .frame(width: 96, height: 72)

            VStack(spacing: 8) {
                title

                subtitle
            }
            .frame(width: 192)

            HStack {

                Button {
                    dismissAction()
                } label: {
                    Text(viewModel.secondaryButtonTitle)
                        .multilineTextAlignment(.center)
                        .padding(.top, 5)
                        .padding(.bottom, 5)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.blackWhite10))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    primaryAction()
                } label: {
                    Text(viewModel.primaryButtonTitle)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 5)
                        .padding(.bottom, 5)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlAccentColor))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 224)
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func primaryAction() {
        viewModel.primaryButtonAction?()
        PixelKit.fire(SyncPromoPixelKitEvent.syncPromoConfirmed.withoutMacPrefix, withAdditionalParameters: ["source": viewModel.touchpointType.rawValue])
    }

    private func dismissAction() {
        viewModel.dismissButtonAction?()
        PixelKit.fire(SyncPromoPixelKitEvent.syncPromoDismissed.withoutMacPrefix, withAdditionalParameters: ["source": viewModel.touchpointType.rawValue])
    }
}

#if DEBUG

#Preview("Compact") {
    SyncPromoView(viewModel: SyncPromoViewModel(touchpointType: .bookmarks, primaryButtonAction: {}, dismissButtonAction: {}),
                  layout: .compact)
        .frame(height: 115)
}

#Preview("Horizontal") {
    SyncPromoView(viewModel: SyncPromoViewModel(touchpointType: .bookmarks, primaryButtonAction: {}, dismissButtonAction: {}),
                  layout: .horizontal)
        .frame(height: 80)
}

#Preview("Vertical") {
    SyncPromoView(viewModel: SyncPromoViewModel(touchpointType: .bookmarks, primaryButtonAction: {}, dismissButtonAction: {}),
                  layout: .vertical)
        .frame(height: 300)
}

@available(macOS 12.0, *)
#Preview("Auto") {
    ResizablePreviewView(maxSize: CGSize(width: 500, height: 500),
                         minSize: CGSize(width: 224, height: 80)) {
        SyncPromoView(viewModel: SyncPromoViewModel(touchpointType: .bookmarks, primaryButtonAction: {}, dismissButtonAction: {}),
                      layout: .auto)
    }
}

#endif
