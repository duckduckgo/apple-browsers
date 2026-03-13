//
//  TabBackgroundView.swift
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

import Cocoa

/// Renders the Tab Background Shape + Hover Overlay, driving state-based animations for selection, highlight, and drag.
final class TabBackgroundView: NSView {

    // MARK: - Constants

    private enum Animations {
        static let duration: TimeInterval = 0.25
        static let opacityVisible: Float = 1
        static let opacityHidden: Float = 0
        static let overlayOpacityVisible: Float = 0.8
        static let slideScaleDown: CGFloat = 0.92
        static let slideScaleFull: CGFloat = 1
        static let slideOffsetY: CGFloat = -8
    }

    private enum Metrics {
        static let overlayCornerRadius: CGFloat = 6
        static let overlayInsets: NSEdgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        static let shapeCornerRadius: CGFloat = 8
        static let shapeRampSize = NSSize(width: 10, height: 10)
    }

    // MARK: - Subviews

    private let backgroundShapeView = TabBackgroundShapeView()
    private let overlayView = ColorView(frame: .zero)

    // MARK: - State

    private var state: TabBackgroundState = .idle {
        didSet {
            guard state != oldValue else { return }

            applyStateChange(oldValue, entering: false)
            applyStateChange(state, entering: true)
        }
    }

    // MARK: - Public Properties

    var backgroundColor: NSColor {
        get {
            backgroundShapeView.backgroundColor
        }
        set {
            backgroundShapeView.backgroundColor = newValue
        }
    }

    var overlayColor: NSColor? {
        get {
            overlayView.backgroundColor
        }
        set {
            overlayView.backgroundColor = newValue
        }
    }

    // MARK: - Initializers

    override init(frame: NSRect) {
        super.init(frame: frame)

        addSubview(overlayView)
        addSubview(backgroundShapeView)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported!")
    }

    override func layout() {
        super.layout()
        layoutBackground()
        layoutOverlay()
    }
}

// MARK: - Private Helpers

private extension TabBackgroundView {

    func setupView() {
        wantsLayer = true

        backgroundShapeView.wantsLayer = true
        backgroundShapeView.rampSize = Metrics.shapeRampSize
        backgroundShapeView.tabCornerRadius = Metrics.shapeCornerRadius

        overlayView.cornerRadius = Metrics.overlayCornerRadius

        // By default, both Background + Overlay will not be visible
        backgroundShapeView.alphaValue = .zero
        overlayView.alphaValue = .zero
    }

    func layoutBackground() {
        backgroundShapeView.frame = bounds

        guard let layer = backgroundShapeView.layer else {
            assertionFailure()
            return
        }

        let anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if layer.anchorPoint != anchorPoint {
            layer.anchorPoint = anchorPoint
        }

        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func layoutOverlay() {
        let insets = Metrics.overlayInsets
        let width = bounds.width - insets.left - insets.right
        let height = bounds.height - insets.top - insets.bottom
        let originX = bounds.origin.x + insets.left
        let originY = bounds.origin.y + insets.top

        overlayView.frame = NSRect(x: originX, y: originY, width: width, height: height)
    }
}

// MARK: - State Machine Management

extension TabBackgroundView {

    func performAnimationIfNeeded(isSelected: Bool, isDragged: Bool, isMouseOver: Bool) {
        state = TabBackgroundState.nextState(isMouseOver: isMouseOver, isSelected: isSelected, isDragged: isDragged)
    }

    private func applyStateChange(_ state: TabBackgroundState, entering: Bool) {
        switch state {
        case .highlighted:
            performOverlayAnimation(visible: entering)
        case .selected:
            performBackgroundAnimation(visible: entering)
        case .dragged:
            backgroundShapeView.isDragged = entering
        case .idle:
            break
        }
    }
}

// MARK: - Animations

extension TabBackgroundView {

    private func performOverlayAnimation(visible: Bool) {
        guard let layer = overlayView.layer else {
            return
        }

        let duration = Animations.duration
        let fromAlpha = layer.presentation()?.opacity ?? layer.opacity
        let toAlpha = visible ? Animations.overlayOpacityVisible : Animations.opacityHidden
        let animation = CASpringAnimation.buildFadeAnimation(duration: duration, fromAlpha: fromAlpha, toAlpha: toAlpha)

        layer.add(animation, forKey: "overlayAnimation")
        layer.opacity = toAlpha
    }

    private func performBackgroundAnimation(visible: Bool) {
        guard let layer = backgroundShapeView.layer else {
            return
        }

        let duration = Animations.duration
        let toAlpha = visible ? Animations.opacityVisible : Animations.opacityHidden

        let fadeAnimation: CASpringAnimation = .buildFadeAnimation(duration: duration, fromAlpha: layer.opacity, toAlpha: toAlpha)

        let translationAnimation: CABasicAnimation = visible
            ? .buildTranslationYAnimation(duration: duration, fromValue: Animations.slideOffsetY, toValue: .zero)
            : .buildTranslationYAnimation(duration: duration, toValue: Animations.slideOffsetY)

        let scaleAnimation: CABasicAnimation = visible
            ? .buildScaleAnimation(duration: duration, fromValue: Animations.slideScaleDown, toValue: Animations.slideScaleFull)
            : .buildScaleAnimation(duration: duration, fromValue: Animations.slideScaleFull, toValue: Animations.slideScaleDown)

        let group = CAAnimationGroup()
        group.animations = [translationAnimation, fadeAnimation, scaleAnimation]
        group.duration = duration

        layer.add(group, forKey: "shapeAnimation")
        layer.opacity = toAlpha
    }
}

// MARK: - Rendering State

private enum TabBackgroundState {
    case idle
    case highlighted
    case selected
    case dragged
}

private extension TabBackgroundState {

    static func nextState(isMouseOver: Bool, isSelected: Bool, isDragged: Bool) -> TabBackgroundState {
        if isSelected {
            return .selected
        }

        if isDragged {
            return .dragged
        }

        if isMouseOver {
            return .highlighted
        }

        return .idle
    }
}
