//
//  AIChatUsageWarningRingView.swift
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
import AppKit
import DesignResourcesKit

/// How much of the allowance is spent, on the approaching message. AppKit twin of iOS's
/// `UTIFooterUsageRingView`: same size, line width, timing and colour table.
final class AIChatUsageWarningRingView: NSView {

    enum Constants {
        static let size: CGFloat = 16
    }

    private enum Metrics {
        static let lineWidth: CGFloat = 2
        static let progressChangeDuration: TimeInterval = 0.25
    }

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    private var progress: Double = 0
    private var severity: DuckAiUsageSeverity = .info

    override var intrinsicContentSize: NSSize {
        NSSize(width: Constants.size, height: Constants.size)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = NSColor.clear.cgColor
            shape.lineWidth = Metrics.lineWidth
            shape.lineCap = .round
            layer?.addSublayer(shape)
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
        animation.duration = Metrics.progressChangeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progressLayer.strokeEnd = clamped
        progressLayer.add(animation, forKey: "strokeEnd")
    }

    override func layout() {
        super.layout()

        let inset = Metrics.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGMutablePath()
        // Starts at twelve o'clock and fills clockwise. AppKit's y runs up, so the sweep ends a full
        // turn *below* the start angle rather than above it as on iOS.
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .pi / 2,
                    endAngle: .pi / 2 - 2 * .pi,
                    clockwise: true)

        for shape in [trackLayer, progressLayer] {
            shape.frame = bounds
            shape.path = path
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        // `CGColor` resolves once, so the drawing appearance has to be current when it is read.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            trackLayer.strokeColor = NSColor(designSystemColor: .lines).cgColor
            progressLayer.strokeColor = NSColor(designSystemColor: Self.progressColor(for: severity)).cgColor
        }
    }

    /// The status triad, so the ring reads the same as the Duck.ai web app's: green, then orange, then
    /// red. iOS still steps grey → yellow → red; its palette has no orange to move to.
    private static func progressColor(for severity: DuckAiUsageSeverity) -> DesignSystemColor {
        switch severity {
        case .info: return .statusGreen
        case .warning: return .statusYellowPrimary
        case .critical, .reached: return .statusRed
        }
    }
}
