//
//  AnyViewModifier.swift
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

/// A type-erased ``ViewModifier``. Lets a component apply a caller-supplied modifier without knowing
/// its concrete type — the caller decides the effect, the component just applies it.
public struct AnyViewModifier: ViewModifier {
    private let apply: (Content) -> AnyView

    public init<Modifier: ViewModifier>(_ modifier: Modifier) {
        apply = { AnyView($0.modifier(modifier)) }
    }

    public func body(content: Content) -> some View {
        apply(content)
    }
}
