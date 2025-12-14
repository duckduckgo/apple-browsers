//
//  DesignSystemImages.swift
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

#if canImport(UIKit)
import UIKit
public typealias DesignSystemImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias DesignSystemImage = NSImage
#else
#error("Unsupported platform")
#endif

public enum DesignSystemImages { }

#if canImport(UIKit)

extension DesignSystemImage {

    /// This assumes the current image is correctly setup as a symbol.  See the check recolorable 24 asset i the design system images as an example.
    /// * If your image only contains one color (and the rest is transparency) then simply set the foreground.
    /// * if your image has two colors thwn use foreground and background
    /// * If your image has three colors then use foreground, middle and background
    /// * If your image has more than three colors, then you should be using smomething else probably
    public func applyPalleteColorsToSymbol(foreground: UIColor, middle: UIColor = .clear, background: UIColor = .clear) -> DesignSystemImage {
        let symbolColorConfiguration = UIImage.SymbolConfiguration(paletteColors: [
            foreground, // e.g. the check
            middle, // usually does nothing in this palette
            background, // e.g. the filled background of the circle
        ])

        guard let image = self.applyingSymbolConfiguration(symbolColorConfiguration) else {
            assertionFailure("Failed to apply symbol configuration")
            return self
        }
        return image
    }

}
#endif
