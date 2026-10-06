//
//  FocusedContentDismissFade.swift
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

/// Fades transient content (logo, suggestion list) out as the host collapses back to the NTP, so it
/// hands off to the NTP content instead of snapping away. Favorites are excluded — they hand off via
/// the embedded-copy reveal, not a fade.
///
/// One-directional: only the fade-*out* (false→true) animates. The reset (true→false, on the next
/// focus) snaps, so the logo reappears instantly instead of replaying a fade-in.
struct FocusedContentDismissFade: ViewModifier {
    let isFadingOut: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isFadingOut ? 0 : 1)
            .animation(isFadingOut ? .easeInOut(duration: 0.2) : nil, value: isFadingOut)
    }
}
