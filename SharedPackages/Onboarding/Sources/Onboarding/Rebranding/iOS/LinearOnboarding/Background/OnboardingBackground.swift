//
//  OnboardingBackground.swift
//  DuckDuckGo
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

#if os(iOS)
import SwiftUI

extension OnboardingRebranding {
    struct OnboardingBackground: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            GeometryReader { proxy in
                Image(.onboardingBackground)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(colorScheme == .light ? 0.5 : 0.3)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                    .background(
                        OnboardingGradient()
                            .ignoresSafeArea()
                    )
            }
        }
    }
}

#Preview("Light Mode") {
    OnboardingRebranding.OnboardingBackground()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode - Highlights") {
    OnboardingRebranding.OnboardingBackground()
        .preferredColorScheme(.dark)
}
#endif
