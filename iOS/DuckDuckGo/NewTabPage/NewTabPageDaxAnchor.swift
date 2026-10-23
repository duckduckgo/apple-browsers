//
//  NewTabPageDaxAnchor.swift
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

/// Where a New Tab Page currently draws Dax's circle, in window coordinates. It comes from SwiftUI
/// layout, so the tab switcher transition can carry Dax between the page and its cell as a layer of
/// its own without knowing how the page lays itself out.
final class NewTabPageDaxAnchor {
    fileprivate(set) var circle: CGRect?
}

private struct DaxCircleKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

extension View {

    /// Reports Dax's circle to `anchor`; `circle` finds it within this view's frame.
    func reportingDaxCircle(to anchor: NewTabPageDaxAnchor?, circle: @escaping (CGRect) -> CGRect = { $0 }) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: DaxCircleKey.self, value: circle(proxy.frame(in: .global)))
        })
        .onPreferenceChange(DaxCircleKey.self) { anchor?.circle = $0 }
    }
}
