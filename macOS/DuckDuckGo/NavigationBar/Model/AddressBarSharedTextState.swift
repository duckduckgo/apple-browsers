//
//  AddressBarSharedTextState.swift
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

import AppKit
import Combine

/// Manages shared text state between search mode and duck.ai mode in the address bar.
/// This allows text content to be shared when switching between modes.
final class AddressBarSharedTextState: ObservableObject {
    
    /// The current text content shared between modes
    @Published private(set) var text: String = ""
    
    /// Whether the user has typed anything (triggers text sharing between modes)
    @Published private(set) var hasUserInteractedWithText: Bool = false
    
    /// Resets the shared state to initial values
    func reset() {
        text = ""
        hasUserInteractedWithText = false
    }
    
    /// Updates the shared text content
    /// - Parameters:
    ///   - newText: The new text value
    ///   - markInteraction: Whether to mark this as a user interaction (defaults to true)
    func updateText(_ newText: String, markInteraction: Bool = true) {
        text = newText
        if markInteraction && !newText.isEmpty {
            hasUserInteractedWithText = true
        }
    }
}
