//
//  View+ScrollBounceBehavior.swift
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

public extension View {

    /// Stops a `ScrollView` from bouncing when its content is small enough to fit fully inside the visible bounds.
    ///
    /// By default a `ScrollView` always rubber-bands, which makes short content look scrollable when it is not.
    /// On macOS 12 and 13.0–13.2 this is a no-op, because `scrollBounceBehavior(_:)` needs macOS 13.3.
    @ViewBuilder
    func scrollBounceBasedOnSize() -> some View {
        if #available(macOS 13.3, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}
