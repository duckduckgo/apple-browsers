//
//  UIColorExtension.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import UIKit

extension UIColor {

    public func combine(withColor other: UIColor, ratio: CGFloat) -> UIColor {
        let otherRatio = 1 - ratio
        let red = (redComponent * ratio) + (other.redComponent * otherRatio)
        let green = (greenComponent * ratio) + (other.greenComponent * otherRatio)
        let blue = (blueComponent * ratio) + (other.blueComponent * otherRatio)
        let alpha = (alphaComponent * ratio) + (other.alphaComponent * otherRatio)
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var redComponent: CGFloat {
        var redComponent: CGFloat = 0
        getRed(&redComponent, green: nil, blue: nil, alpha: nil)
        return redComponent
    }

    public var greenComponent: CGFloat {
        var greenComponent: CGFloat = 0
        getRed(nil, green: &greenComponent, blue: nil, alpha: nil)
        return greenComponent
    }

    public var blueComponent: CGFloat {
        var blueComponent: CGFloat = 0
        getRed(nil, green: nil, blue: &blueComponent, alpha: nil)
        return blueComponent
    }

    public var alphaComponent: CGFloat {
        var alphaComponent: CGFloat = 0
        getRed(nil, green: nil, blue: nil, alpha: &alphaComponent)
        return alphaComponent
    }

}

extension UIColor {

    public static func forDomain(_ domain: String) -> UIColor {
        var consistentHash: Int {
            return domain.utf8
                .map { return $0 }
                .reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        }

        let palette = [
            UIColor(hex: "94B3AF"),
            UIColor(hex: "727998"),
            UIColor(hex: "645468"),
            UIColor(hex: "4D5F7F"),
            UIColor(hex: "855DB6"),
            UIColor(hex: "5E5ADB"),
            UIColor(hex: "678FFF"),
            UIColor(hex: "6BB4EF"),
            UIColor(hex: "4A9BAE"),
            UIColor(hex: "66C4C6"),
            UIColor(hex: "55D388"),
            UIColor(hex: "99DB7A"),
            UIColor(hex: "ECCC7B"),
            UIColor(hex: "E7A538"),
            UIColor(hex: "DD6B4C"),
            UIColor(hex: "D65D62")
        ]

        let hash = consistentHash
        let index = hash % palette.count
        return palette[abs(index)]
    }

    private convenience init(hex: String) {
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }

    /// Adjusts the brightness of the color by the specified amount
    /// - Parameter amount: Value between -1.0 and 1.0. Positive values make the color brighter, negative values make it darker
    /// - Returns: A new UIColor with adjusted brightness
    func adjustBrightness(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // Convert to HSB color space
        if self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            // Adjust brightness, keeping it within 0-1 range
            let newBrightness = max(0, min(1, brightness + amount))
            return UIColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha)
        }

        // Fallback for colors that can't be converted to HSB
        return self
    }

    var brightnessPercentage: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r * 299 + g * 587 + b * 114) / 1000 * 100
    }

}
