//
//  RebrandedPreview.swift
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

#if DEBUG

import SwiftUI

/// Wraps SwiftUI preview content so the rebranded design-system palette is active, matching the runtime
/// appearance of the post-subscription onboarding flow. Shared by the onboarding view previews.
struct RebrandedPreview<Content: View>: View {
    @StateObject private var rebrandOverride = RebrandPreviewOverride(isRebranded: true)
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .onAppear { rebrandOverride.apply() }
    }
}

#endif
