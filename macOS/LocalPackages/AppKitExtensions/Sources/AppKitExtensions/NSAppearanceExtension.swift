//
//  NSAppearanceExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Cocoa

public extension NSAppearance {

    /// Executes a given closure, while resolving the Colors against `NSApp.effectiveAppearance`
    ///
    static func withAppAppearance(_ closure: () -> Void) {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance(closure)
    }

    /// Executes a given closure, while resolving the Colors against the specified `NSView.appearance` value.
    /// Otherwise, we'll fallback to `NSApp.effectiveAppearance`.
    ///
    static func withAppearance(from view: NSView, _ closure: () -> Void) {
        withAppearance(view.appearance, closure)
    }

    /// Executes a given closure, while resolving the Colors against the explicitly specified Appearance.
    /// Otherwise, we'll fallback to `NSApp.effectiveAppearance`.
    ///
    static func withAppearance(_ appearance: NSAppearance?, _ closure: () -> Void) {
        guard let appearance else {
            withAppAppearance(closure)
            return
        }

        appearance.performAsCurrentDrawingAppearance(closure)
    }
}
