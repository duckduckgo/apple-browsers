//
//  CreditCardPromptView.swift
//  DuckDuckGo
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

import DesignResourcesKit
import SwiftUI

struct CreditCardPromptView: View {
    @State var frame: CGSize = .zero
    @State var viewModel: CreditCardPromptViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var orientation = UIDevice.current.orientation
    
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
            
            VStack {
                
                Spacer(minLength: Const.Size.topPadding)
                
                AutofillViews.AppIconHeader()
                
                Spacer(minLength: Const.Size.headlineTopPadding)
                
                AutofillViews.Headline(title: UserText.autofillCreditCardFillPromptTitle)
                
                contentSpacer
                
                ForEach(viewModel.cards, id: \.self) { card in
                    Button {
                        viewModel.selected(card: card)
                    } label: {
                        CreditCardRow(card: card, showDisclosure: false)
                            .padding(EdgeInsets(top: Const.Size.cardVerticalPadding, leading: Const.Size.cardHorizontalPadding, bottom: Const.Size.cardVerticalPadding, trailing: Const.Size.cardHorizontalPadding))
                            .background(Color(designSystemColor: .controlsFillPrimary))
                            .cornerRadius(Const.Size.cornerRadius)
                            .frame(maxWidth: Const.Size.maxWidth)
                    }
                    
                }
                
                bottomSpacer
            }
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
    
    private var contentSpacer: some View {
        VStack {
            if AutofillViews.isIPhoneLandscape(verticalSizeClass) {
                Spacer(minLength: Const.Size.contentSpacerHeight)
            } else {
                AutofillViews.LegacySpacerView(height: Const.Size.headlineToContentSpacing)
            }
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
    
    private var bottomSpacer: some View {
        VStack {
            if AutofillViews.isIPhonePortrait(verticalSizeClass, horizontalSizeClass) {
                AutofillViews.LegacySpacerView(height: Const.Size.bottomSpacerHeight)
            } else if AutofillViews.isIPad(verticalSizeClass, horizontalSizeClass) {
                AutofillViews.LegacySpacerView(height: Const.Size.bottomSpacerHeightIPad)
            } else {
                AutofillViews.LegacySpacerView()
            }
        }
    }
}

private enum Const {
    enum Size {
        static let closeButtonOffset: CGFloat = 48.0
        static let closeButtonOffsetPortrait: CGFloat = 44.0
        static let closeButtonOffsetPortraitSmallFrame: CGFloat = 16.0
        static let topPadding: CGFloat = 56.0
        static let headlineTopPadding: CGFloat = 24.0
        static let contentSpacerHeight: CGFloat = 56.0
        static let headlineToContentSpacing: CGFloat = 24.0
        static let cardHorizontalPadding: CGFloat = 16.0
        static let cardVerticalPadding: CGFloat = 12.0
        static let cornerRadius: CGFloat = 8.0
        static let maxWidth: CGFloat = 480.0
        static let bottomSpacerHeight: CGFloat = 40.0
        static let bottomSpacerHeightIPad: CGFloat = 60.0
    }
}
