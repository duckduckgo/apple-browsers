//
//  ImportPromotionHeaderView.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import Lottie

struct ImportPromotionHeaderView: View {
    var primaryButtonAction: (() -> Void)?
    var dismissButtonAction: (() -> Void)?
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Group {
                    AnimationView(isAnimating: $isAnimating)
                    
                    Text(UserText.importPasswordsPromoTitle)
                        .daxTitle3()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity)

                    (Text(Image(uiImage: DesignSystemImages.Glyphs.Size12.lockSolid)).baselineOffset(-1.0) + Text(verbatim: " ") + Text(UserText.importPasswordsPromoMessage))
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                Button {
                    primaryButtonAction?()
                } label: {
                    HStack {
                        Text(UserText.importPasswordsPromoButtonTitle)
                            .daxButton()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 360)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .padding(.horizontal, 16)

            }
            .multilineTextAlignment(.center)
            .padding(.top)
            .padding(.horizontal, 8)
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismissButtonAction?()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                            .foregroundColor(.primary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(0)
                }
            }
            .alignmentGuide(.top) { dimension in
                dimension[.top]
            }
        }
        .background(RoundedRectangle(cornerRadius: 8.0)
            .foregroundColor(Color(designSystemColor: .surface))
        )
        .onAppear {
            isAnimating = true
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 30)
    }
    
    private struct AnimationView: View {
        @Binding var isAnimating: Bool
        
        var body: some View {
            LottieView(
                lottieFile: "password-keys",
                loopMode: .mode(.repeat(2.0)),
                isAnimating: $isAnimating
            )
            .frame(width: 128, height: 96)
            .aspectRatio(contentMode: .fit)
            .padding(.top, 8)
        }
    }
}

#Preview {
    ImportPromotionHeaderView()
}
