//
//  SearchResultsSkeletonView.swift
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

import UIKit
import DesignResourcesKit

/// Outline of the results page header and first results, shown while a search loads.
///
/// Shapes follow the in-app results page (tabs row, filter row, result blocks) without its words,
/// since the tabs and modules change per query. It only appears if the load isn't near-instant.
final class SearchResultsSkeletonView: UIView {

    enum Constants {
        /// A load that paints within this never shows the skeleton.
        static let appearDelay: TimeInterval = 0.1
        static let appearDuration: TimeInterval = 0.2
        static let pulseDuration: TimeInterval = 0.9
        static let pulseOpacity: Float = 0.65

        static let margin: CGFloat = 17
        static let barHeight: CGFloat = 12

        static let tabsCenterY: CGFloat = 26
        static let tabWidths: [CGFloat] = [18, 46, 40, 44]
        static let tabSpacing: CGFloat = 14
        static let dividerY: CGFloat = 44

        static let filtersCenterY: CGFloat = 66
        static let filterWidths: [CGFloat] = [80, 120, 90]
        static let filterSpacing: CGFloat = 12
        static let filterHeight: CGFloat = 16

        static let resultsTop: CGFloat = 94
        static let resultHeight: CGFloat = 132
        static let faviconSize: CGFloat = 32
    }

    /// Where the page's own content starts, in this view's coordinates; below the address bar when it floats on top.
    var contentTop: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    private let shapes = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        layer.addSublayer(shapes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Fades in after a short delay, then pulses; Reduce Motion keeps it still.
    func appear() {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let slowdown = FirstPaintCover.debugSlowdown
        UIView.animate(withDuration: Constants.appearDuration * slowdown,
                       delay: Constants.appearDelay * slowdown,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.alpha = 1
        }
        guard !reduceMotion else { return }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = Constants.pulseOpacity
        pulse.duration = Constants.pulseDuration * slowdown
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.beginTime = CACurrentMediaTime() + (Constants.appearDelay + Constants.appearDuration) * slowdown
        shapes.add(pulse, forKey: "pulse")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapes.frame = bounds
        shapes.fillColor = UIColor(designSystemColor: .controlsFillSecondary).resolvedColor(with: traitCollection).cgColor
        shapes.path = Self.path(width: bounds.width, height: bounds.height, contentTop: contentTop, scale: traitCollection.displayScale)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    static func path(width: CGFloat, height: CGFloat, contentTop: CGFloat, scale: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let margin = Constants.margin

        func bar(x: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat = Constants.barHeight) {
            let rect = CGRect(x: x, y: centerY - height / 2, width: max(0, width), height: height)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: height / 2))
        }

        // Tabs row and its divider.
        var x = margin
        for tabWidth in Constants.tabWidths {
            bar(x: x, centerY: contentTop + Constants.tabsCenterY, width: tabWidth)
            x += tabWidth + Constants.tabSpacing
        }
        let hairline = 1 / max(scale, 1)
        path.append(UIBezierPath(rect: CGRect(x: 0, y: contentTop + Constants.dividerY, width: width, height: hairline)))

        // Filter row.
        x = margin
        for filterWidth in Constants.filterWidths {
            bar(x: x, centerY: contentTop + Constants.filtersCenterY, width: filterWidth, height: Constants.filterHeight)
            x += filterWidth + Constants.filterSpacing
        }

        // Result blocks: favicon, site and address, title, two snippet lines.
        let textX = margin + Constants.faviconSize + 8
        let contentWidth = width - margin * 2
        var top = contentTop + Constants.resultsTop
        while top < height {
            path.append(UIBezierPath(ovalIn: CGRect(x: margin, y: top, width: Constants.faviconSize, height: Constants.faviconSize)))
            bar(x: textX, centerY: top + 8, width: 60, height: 10)
            bar(x: textX, centerY: top + 25, width: min(170, contentWidth - textX), height: 10)
            bar(x: margin, centerY: top + 56, width: contentWidth * 0.78, height: 16)
            bar(x: margin, centerY: top + 86, width: contentWidth * 0.94)
            bar(x: margin, centerY: top + 106, width: contentWidth * 0.6)
            top += Constants.resultHeight
        }
        return path.cgPath
    }
}
