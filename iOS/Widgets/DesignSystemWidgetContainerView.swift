//
//  DesignSystemWidgetContainerView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

/// Use this view to apply our standard design to widgets.  Ensure that the configuration for the widget uses the `.contentMarginsDisabled()` modifier.
struct DesignSystemWidgetContainerView<Content: View>: View {

    @ViewBuilder
    let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            // Adding a color background here can help debug
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        // Adding a different color background here in addition to the container backgrund can help debug
        .widgetContainerBackground()
    }

}
