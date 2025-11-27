//
//  OmniBarNotification.swift
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
import UIKit

struct OmniBarNotification: View {

    @ObservedObject var viewModel: OmniBarNotificationViewModel

    @State var isAnimatingCookie: Bool = false

    @State var textOffset: CGFloat = 0
    @State var textWidth: CGFloat = 0

    var body: some View {
        HStack {
            HStack(spacing: 0) {
                animation
                text
            }
            .background(
                RoundedRectangle(cornerRadius: Constants.Radius.background)
                    .foregroundColor(Constants.Colors.background)
                    .offset(x: textOffset)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.background))
            )
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var animation: some View {
        if !viewModel.animationName.isEmpty {
            LottieView(lottieFile: viewModel.animationName,
                       isAnimating: $isAnimatingCookie)
                       .frame(width: Constants.Size.animatedIcon.width, height: Constants.Size.animatedIcon.height)
        } else {
            // Static shield icon if no animation is provided
            Image("ShieldColor")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.Size.staticIcon.width, height: Constants.Size.staticIcon.height)
                .padding(.leading, 9)
                .padding(.top, 7)
                .padding(.bottom, 7)
                .padding(.trailing, 9)
        }
    }
    
    @ViewBuilder
    private var text: some View {
        Text(viewModel.text)
            .font(Constants.Fonts.text)
            .foregroundColor(Constants.Colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .offset(x: textOffset)
            .padding(.trailing, Constants.Spacing.textTrailingPadding)
            .clipShape(Rectangle().inset(by: Constants.Spacing.textClippingShapeOffset))
            .onReceive(viewModel.$isOpen) { isOpen in
                withAnimation(.easeInOut(duration: OmniBarNotificationViewModel.Duration.notificationSlide)) {
                    textOffset = isOpen ? 0 : -textWidth
                }
            }
            .onReceive(viewModel.$isAnimating) { isAnimating in
                isAnimatingCookie = isAnimating
            }
            .modifier(SizeModifier())
            .onPreferenceChange(SizePreferenceKey.self) {
                textWidth = $0.width
                // Only reset offset if notification hasn't opened yet (text hasn't slid in)
                if !viewModel.isOpen {
                    textOffset = -textWidth
                }
            }
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct SizeModifier: ViewModifier {
    private var sizeView: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        }
    }

    func body(content: Content) -> some View {
        content.background(sizeView)
    }
}

private enum Constants {
    
    enum Fonts {
        static let text = Font(UIFont.systemFont(ofSize: 16))
    }
    
    enum Colors {
        static let text = Color(UIColor(designSystemColor: .textPrimary))
        static let background = Color(UIColor(designSystemColor: .panel))
    }

    enum Spacing {
        static let textClippingShapeOffset: CGFloat = -7
        static let textTrailingPadding: CGFloat = 12
    }
    
    enum Size {
        static let animatedIcon = CGSize(width: 36, height: 36)
        static let cancel = CGSize(width: 13, height: 13)
        static let rowHeight: CGFloat = 76
        static let staticIcon = CGSize(width: 21, height: 21)
    }

    enum Radius {
        static let background: CGFloat = 12
    }
}
