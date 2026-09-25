//
//  SuggestionsFavoritesView.swift
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

import SwiftUI
import UIKit

/// Keeps focused favorites mounted while the shared resolver switches between content states.
/// Layout owners can reuse the presentation without creating another favorites controller.
struct SuggestionsFavoritesView: View {
    let presentation: FocusedFavoritesPresentation
    let isVisible: Bool

    var body: some View {
        if let controller = presentation.viewController {
            // Extend under the top safe area so the frame stays static; the nested NTP receives
            // its top inset through its scroll view, preserving the existing input animation.
            FavoritesControllerView(controller: controller)
                .ignoresSafeArea(.container, edges: .top)
                // Keep visibility instant during mode changes so favorites do not linger over
                // the incoming Duck.ai list. Keeping it mounted also preserves interrupted toggles.
                .opacity(isVisible ? 1 : 0)
                .animation(nil, value: isVisible)
                .allowsHitTesting(isVisible)
        }
    }
}

private struct FavoritesControllerView: UIViewControllerRepresentable {
    let controller: NewTabPageViewController

    func makeUIViewController(context: Context) -> NewTabPageViewController { controller }
    func updateUIViewController(_ uiViewController: NewTabPageViewController, context: Context) {}
}
