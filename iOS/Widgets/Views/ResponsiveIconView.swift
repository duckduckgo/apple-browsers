//
//  ResponsiveIconView.swift
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
import WidgetKit
import AppIntents
import DesignResourcesKit
import DesignResourcesKitIcons

struct ResponsiveIconView: View {

    let image: Image

    var frameSize: CGFloat {
        return 60
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .renderAwareBackgroundFill()

            image
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color(designSystemColor: .icons))
        }
        .makeAccentable()
        // .frame(width: frameSize, height: frameSize)
        .frame(maxWidth: .infinity)
        .aspectRatio(contentMode: .fit)
    }
}
