//
//  BurnerAppearanceStyle.swift
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

import Foundation
import AppKit

struct BurnerAppearanceStyle {

    func enableDarkModeOverride(in view: NSView) {
        view.appearance = NSAppearance(named: .darkAqua)
        updateResolvesStyleWithEffectiveAppearance(view: view, value: true)
    }

    func disableDarkModeOverride(in view: NSView) {
        view.appearance = nil
        updateResolvesStyleWithEffectiveAppearance(view: view, value: false)
    }
}

private extension BurnerAppearanceStyle {

    /// `ColorView` uses `CALayer` to render its background and border.
    /// As such, it relies upon `NSAppearance.withAppearance` to resolve the right effective color.
    ///
    /// When forcing darkAqua, we must hint `ColorView` to resolve agains the `.effectiveAppearance` property.
    /// Otherwise, it'll pick up `NSApp.effectiveAppearance`, rendering our darkAqua override ineffective.
    ///
    func updateResolvesStyleWithEffectiveAppearance(view: NSView, value: Bool) {
        if let colorView = view as? ColorView {
            colorView.resolvesStyleWithEffectiveAppearance = value
        }

        updateResolvesStyleWithEffectiveAppearance(views: view.subviews, value: value)
    }

    private func updateResolvesStyleWithEffectiveAppearance(views: [NSView], value: Bool) {
        for subview in views {
            if let colorView = subview as? ColorView {
                colorView.resolvesStyleWithEffectiveAppearance = value
            }

            if subview.subviews.isEmpty {
                continue
            }

            updateResolvesStyleWithEffectiveAppearance(views: subview.subviews, value: value)
        }
    }
}
