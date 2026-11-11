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

        /// The outline is solid over the page header, then fades out by the bottom of the screen.
        static let fadeEndOpacity: CGFloat = 0

        /// Results page margins: narrow pages run edge to edge, wider ones indent a capped column.
        static let wideLayoutMinPageWidth: CGFloat = 590
        static let widestLayoutMinPageWidth: CGFloat = 1079
        static let narrowMargin: CGFloat = 17
        static let wideLeadingMargin: CGFloat = 74
        static let widestLeadingMargin: CGFloat = 110
        static let wideTrailingMargin: CGFloat = 30
        static let maxColumnWidth: CGFloat = 652
        static let barHeight: CGFloat = 12

        static let tabsCenterY: CGFloat = 26
        static let tabWidths: [CGFloat] = [18, 46, 40, 44]
        static let tabSpacing: CGFloat = 14
        static let dividerY: CGFloat = 44

        static let filtersCenterY: CGFloat = 66
        static let filterWidths: [CGFloat] = [80, 120, 90]
        static let filterSpacing: CGFloat = 12
        static let filterHeight: CGFloat = 16

        /// Tabs and filters, down to just above the first result.
        static let headerHeight: CGFloat = 88
        static let resultsTop: CGFloat = 94
        static let resultHeight: CGFloat = 132
        static let faviconSize: CGFloat = 32
    }

    /// Where the page's own content starts, in this view's coordinates; below the address bar when it floats on top.
    var contentTop: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    /// The real header as it last rendered; shown in place of its outline while it matches this width.
    var headerImage: UIImage? {
        didSet {
            headerView.image = headerImage
            setNeedsLayout()
        }
    }

    /// The web view being covered; the page lays out in its frame, inside its horizontal safe area.
    weak var pageView: UIView? {
        didSet { setNeedsLayout() }
    }

    private let shapes = CAShapeLayer()
    private let headerView = UIImageView()
    private let fade = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        layer.addSublayer(shapes)
        headerView.isAccessibilityElement = false
        addSubview(headerView)
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = fade
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
        let pageFrame = pageView.map { convert($0.bounds, from: $0) } ?? bounds
        let pageSafeArea = pageView?.safeAreaInsets ?? safeAreaInsets
        let pageInsets = (left: pageFrame.minX + pageSafeArea.left, right: bounds.maxX - pageFrame.maxX + pageSafeArea.right)

        let showsHeaderImage = headerImage.map { SearchPageHeaderMemory.matches($0, width: pageFrame.width) } ?? false
        headerView.isHidden = !showsHeaderImage
        headerView.frame = CGRect(x: pageFrame.minX, y: contentTop, width: pageFrame.width, height: headerImage?.size.height ?? 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapes.frame = bounds
        shapes.fillColor = UIColor(designSystemColor: .controlsFillSecondary).resolvedColor(with: traitCollection).cgColor
        shapes.path = Self.path(width: bounds.width,
                                height: bounds.height,
                                contentTop: contentTop,
                                scale: traitCollection.displayScale,
                                pageInsets: pageInsets,
                                includesHeader: !showsHeaderImage)
        fade.frame = bounds
        fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.black.withAlphaComponent(Constants.fadeEndOpacity).cgColor]
        fade.locations = Self.fadeLocations(height: bounds.height, contentTop: contentTop)
        CATransaction.commit()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// Solid down to the first result, then fading to the bottom edge.
    static func fadeLocations(height: CGFloat, contentTop: CGFloat) -> [NSNumber] {
        guard height > 0 else { return [0, 0, 1] }
        let solidUntil = min(max((contentTop + Constants.resultsTop) / height, 0), 1)
        return [0, NSNumber(value: Double(solidUntil)), 1]
    }

    /// Where the results page puts its content column, measured from the page's leading edge.
    static func contentColumn(pageWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        guard pageWidth > Constants.wideLayoutMinPageWidth else {
            return (Constants.narrowMargin, max(0, pageWidth - Constants.narrowMargin * 2))
        }
        let leading = pageWidth > Constants.widestLayoutMinPageWidth ? Constants.widestLeadingMargin : Constants.wideLeadingMargin
        let available = pageWidth - leading - Constants.wideTrailingMargin
        return (leading, min(available, Constants.maxColumnWidth))
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    static func path(width: CGFloat,
                     height: CGFloat,
                     contentTop: CGFloat,
                     scale: CGFloat,
                     pageInsets: (left: CGFloat, right: CGFloat) = (0, 0),
                     includesHeader: Bool = true) -> CGPath {
        let path = UIBezierPath()
        let pageWidth = max(0, width - pageInsets.left - pageInsets.right)
        let column = contentColumn(pageWidth: pageWidth)
        let margin = pageInsets.left + column.x

        func bar(x: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat = Constants.barHeight) {
            let rect = CGRect(x: x, y: centerY - height / 2, width: max(0, width), height: height)
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: height / 2))
        }

        if includesHeader {
            // Tabs row and its divider.
            var x = margin
            for tabWidth in Constants.tabWidths {
                bar(x: x, centerY: contentTop + Constants.tabsCenterY, width: tabWidth)
                x += tabWidth + Constants.tabSpacing
            }
            let hairline = 1 / max(scale, 1)
            path.append(UIBezierPath(rect: CGRect(x: pageInsets.left, y: contentTop + Constants.dividerY, width: pageWidth, height: hairline)))

            // Filter row.
            x = margin
            for filterWidth in Constants.filterWidths {
                bar(x: x, centerY: contentTop + Constants.filtersCenterY, width: filterWidth, height: Constants.filterHeight)
                x += filterWidth + Constants.filterSpacing
            }
        }

        // Result blocks: favicon, site and address, title, two snippet lines.
        let textX = margin + Constants.faviconSize + 8
        let contentWidth = column.width
        var top = contentTop + Constants.resultsTop
        while top < height {
            path.append(UIBezierPath(ovalIn: CGRect(x: margin, y: top, width: Constants.faviconSize, height: Constants.faviconSize)))
            bar(x: textX, centerY: top + 8, width: 60, height: 10)
            bar(x: textX, centerY: top + 25, width: min(170, contentWidth - Constants.faviconSize - 8), height: 10)
            bar(x: margin, centerY: top + 56, width: contentWidth * 0.78, height: 16)
            bar(x: margin, centerY: top + 86, width: contentWidth * 0.94)
            bar(x: margin, centerY: top + 106, width: contentWidth * 0.6)
            top += Constants.resultHeight
        }
        return path.cgPath
    }
}
