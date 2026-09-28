//
//  UTIFooterUsageRingView.swift
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

import AIChat
import DesignResourcesKit
import UIKit

final class UTIFooterUsageRingView: UIView {

    private enum Constants {
        static let size: CGFloat = 16
        static let lineWidth: CGFloat = 2
        static let progressChangeDuration: TimeInterval = 0.25
    }

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    private var progress: Double = 0
    private var severity: DuckAiUsageSeverity = .info

    override var intrinsicContentSize: CGSize {
        CGSize(width: Constants.size, height: Constants.size)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = Constants.lineWidth
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        progressLayer.strokeEnd = 0
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setProgress(_ progress: Double, severity: DuckAiUsageSeverity, animated: Bool) {
        if severity != self.severity {
            self.severity = severity
            applyColors()
        }
        let clamped = min(max(progress, 0), 1)
        guard clamped != self.progress else { return }
        self.progress = clamped
        guard animated else {
            progressLayer.removeAnimation(forKey: "strokeEnd")
            progressLayer.strokeEnd = clamped
            return
        }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = progressLayer.presentation()?.value(forKey: "strokeEnd") ?? progressLayer.strokeEnd
        animation.toValue = clamped
        animation.duration = Constants.progressChangeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progressLayer.strokeEnd = clamped
        progressLayer.add(animation, forKey: "strokeEnd")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Constants.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = UIBezierPath(arcCenter: CGPoint(x: rect.midX, y: rect.midY),
                                radius: min(rect.width, rect.height) / 2,
                                startAngle: -.pi / 2,
                                endAngle: 3 * .pi / 2,
                                clockwise: true).cgPath
        for shape in [trackLayer, progressLayer] {
            shape.frame = bounds
            shape.path = path
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyColors()
        }
    }

    private func applyColors() {
        trackLayer.strokeColor = UIColor(designSystemColor: .lines).cgColor
        progressLayer.strokeColor = UIColor(designSystemColor: Self.progressColor(for: severity)).cgColor
    }

    /// Follows the Duck.ai web app's green → orange → red, as far as this palette goes: it has no
    /// orange, so the middle step stays yellow where macOS uses one.
    private static func progressColor(for severity: DuckAiUsageSeverity) -> DesignSystemColor {
        switch severity {
        case .info: return .alertGreen
        case .warning: return .alertYellow
        case .critical, .reached: return .destructivePrimary
        }
    }
}
