//
//  NewTabPageDaxLogoView.swift
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

import Lottie
import SwiftUI

struct NewTabPageDaxLogoView: View {
    @Environment(\.colorScheme) private var colorScheme

    var daxAnchor: NewTabPageDaxAnchor?

    private var animationName: String {
        colorScheme == .dark ? "duckduckgo-ai-transition-dark.json" : "duckduckgo-ai-transition.json"
    }

    var body: some View {
        Lottie.LottieView(animation: LottieAnimation.named(animationName))
            .playbackMode(.paused(at: .progress(0)))
            .frame(height: 162)
            .reportingDaxCircle(to: daxAnchor, circle: Self.daxCircle(inAnimationFrame:))
            .id(animationName)
    }

    /// Where the duck's circle is drawn within the aspect-fitted animation. Every variant of the
    /// animation shares the same composition: a 2100×1620 canvas with the circle (radius 470) centred
    /// at (1058, 630).
    private static func daxCircle(inAnimationFrame frame: CGRect) -> CGRect {
        let canvas = CGSize(width: 2100, height: 1620)
        let scale = min(frame.width / canvas.width, frame.height / canvas.height)
        let center = CGPoint(x: frame.midX + (1058 - canvas.width / 2) * scale,
                             y: frame.midY + (630 - canvas.height / 2) * scale)
        let radius = 470 * scale
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

#Preview {
    NewTabPageDaxLogoView()
}
