//
//  ResizableTintableImage.swift
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

struct ResizableTintableImage: View {

    // Design system images are UIImage (would prefer to use ImageResource)
    let fullColor: UIImage
    let tintable: UIImage

    var body: some View {
        Group {
            if #available(iOS 16, *) {
                RenderingAwareImage(fullColor: fullColor, tintable: tintable)
            } else {
                Image(uiImage: fullColor)
                    .resizable()
                    .useFullColorRendering()
            }
        }
        .aspectRatio(contentMode: .fit)
    }

}

@available(iOSApplicationExtension 16, *)
private struct RenderingAwareImage: View {

    @Environment(\.widgetRenderingMode) var widgetRenderingMode
    let fullColor: UIImage
    let tintable: UIImage

    var body: some View {
        if widgetRenderingMode == .fullColor {
            Image(uiImage: fullColor)
                .resizable()
                .useFullColorRendering()
        } else {
            Image(uiImage: tintable)
                .resizable()
                .makeAccentable()
        }
    }

}
