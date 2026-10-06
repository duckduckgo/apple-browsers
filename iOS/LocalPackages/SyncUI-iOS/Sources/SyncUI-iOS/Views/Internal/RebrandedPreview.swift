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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// Scoped rebrand override for previews.
///
/// `AppRebrand.isAppRebranded` defaults to `{ false }` and is only flipped to a live feature-flag
/// lookup by the host app at launch — which previews never run. So without an override, previews
/// always show the legacy artwork/palette. This captures the previous values at init and restores
/// them on deinit, so one preview doesn't leak its brand state into the others. Mirrors DuckUI's
/// internal `RebrandPreviewOverride`.
private final class RebrandPreviewOverride: ObservableObject {
    private let previousIsRebranded: () -> Bool
    private let previousPalette: ColorPalette

    init(isRebranded: Bool) {
        previousIsRebranded = AppRebrand.isAppRebranded
        previousPalette = DesignSystemPalette.current
        AppRebrand.isAppRebranded = { isRebranded }
        DesignSystemPalette.current = isRebranded ? .rebranded : .default
    }

    deinit {
        AppRebrand.isAppRebranded = previousIsRebranded
        DesignSystemPalette.current = previousPalette
    }
}

/// Wraps preview content so it renders with the rebrand flag *and* the design-system palette
/// (button/tint fills resolve through `DesignSystemPalette.current`) set to `isRebranded`.
struct RebrandedPreview<Content: View>: View {
    private let isRebranded: Bool
    @StateObject private var override: RebrandPreviewOverride
    private let content: Content

    init(isRebranded: Bool, @ViewBuilder content: () -> Content) {
        self.isRebranded = isRebranded
        _override = StateObject(wrappedValue: RebrandPreviewOverride(isRebranded: isRebranded))
        self.content = content()
    }

    var body: some View {
        // Re-assert at body time so the flag is set before child views resolve their images.
        AppRebrand.isAppRebranded = { isRebranded }
        DesignSystemPalette.current = isRebranded ? .rebranded : .default
        return content
    }
}

#endif
