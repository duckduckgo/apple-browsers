//
//  View+LegacyOnDismiss.swift
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

public extension View {

    /// Wires up a dismiss action for SwiftUI views hosted inside AppKit presentations (popovers, modal windows,
    /// sheets) on macOS 12 and 13, where Apple's `EnvironmentValues.dismiss` doesn't reach the hosting AppKit
    /// container. On macOS 14+ this is a no-op because the native `dismiss` works on its own.
    @available(macOS, obsoleted: 14.0, message: "This needs to be removed as it‘s no longer necessary.")
    @ViewBuilder
    func legacyOnDismiss(_ onDismiss: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self

        } else if let presentationModeKey = \EnvironmentValues.presentationMode as? WritableKeyPath {
            // hacky way to set the @Environment.presentationMode.
            // here we downcast a (non-writable) \.presentationMode KeyPath to a WritableKeyPath
            self.environment(presentationModeKey, Binding<PresentationMode>(onDismiss: onDismiss))

        } else {
            // Fallback if the downcast ever fails: render the content unchanged rather than an empty view.
            self
        }
    }
}

public extension Binding where Value == PresentationMode {

    init(isPresented: Bool = true, onDismiss: @escaping () -> Void) {
        // PresentationMode is a struct with a single isPresented property and a (statically dispatched) mutating function
        // This technically makes it equal to a Bool variable (MemoryLayout<PresentationMode>.size == MemoryLayout<Bool>.size == 1)
        var isPresented = isPresented
        self.init {
            // just return the Bool as a PresentationMode
            unsafeBitCast(isPresented, to: PresentationMode.self)
        } set: { newValue in
            // set it back
            isPresented = newValue.isPresented
            // and call the dismiss callback
            if !isPresented {
                onDismiss()
            }
        }
    }

}
