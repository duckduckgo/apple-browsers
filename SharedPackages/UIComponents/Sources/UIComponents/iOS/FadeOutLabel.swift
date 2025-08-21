//
//  FadeOutLabel.swift
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

#if os(iOS)

import UIKit

// Based on https://stackoverflow.com/a/53847223/73479
public class FadeOutLabel: UILabel {

    override public var textColor: UIColor! {
        get { primaryColor }
        set { primaryColor = newValue }
    }

    public var primaryColor: UIColor = .black {
        didSet {
            setNeedsDisplay()
        }
    }

    public override func drawText(in rect: CGRect) {

        // Fade out only when the content exceeds the width of target rect
        if intrinsicContentSize.width > rect.width {
            let gradientColors = [primaryColor.cgColor, UIColor.clear.cgColor]
            if let gradientColor = drawGradientColor(in: rect, colors: gradientColors) {
                super.textColor = gradientColor
            }
        } else {
            super.textColor = primaryColor
        }

        super.drawText(in: rect)
    }

    private func drawGradientColor(in rect: CGRect, colors: [CGColor]) -> UIColor? {
        let currentContext = UIGraphicsGetCurrentContext()
        currentContext?.saveGState()
        defer { currentContext?.restoreGState() }

        let size = rect.size
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: [0.8, 1]) else { return nil }

        let context = UIGraphicsGetCurrentContext()
        context?.drawLinearGradient(gradient,
                                    start: .zero,
                                    end: CGPoint(x: size.width, y: 0),
                                    options: [])
        let gradientImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let image = gradientImage else { return nil }
        return UIColor(patternImage: image)
    }

}
#endif
