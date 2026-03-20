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
        static let duration: TimeInterval = 0.15
        static let opacityVisible: Float = 1
        static let opacityHidden: Float = 0
        static let overlayKey = "overlayAnimation"
        static let overlayOpacityVisible: Float = 0.8
        static let shapeKey = "shapeAnimation"
        static let slideScaleDown: CGFloat = 0.92
        static let slideScaleFull: CGFloat = 1
        static let slideOffsetY: CGFloat = -8
    }

    private enum Metrics {
        static let overlayCornerRadius: CGFloat = 8
        static let overlayInsets: NSEdgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        static let tabCornerRadius: CGFloat = 12
        static let tabRampSize = NSSize(width: 12, height: 12)
    }

    // MARK: - Subviews

    private let backgroundShapeView = TabBackgroundShapeView()
    private let overlayView = ColorView(frame: .zero)

    // MARK: - State

    private var state: TabBackgroundState = .idle

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
        clipsToBounds = false

        backgroundShapeView.wantsLayer = true
        backgroundShapeView.clipsToBounds = false
        backgroundShapeView.tabRampSize = Metrics.tabRampSize
        backgroundShapeView.tabCornerRadius = Metrics.tabCornerRadius

        overlayView.cornerRadius = Metrics.overlayCornerRadius

        // By default, both Background + Overlay will not be visible
        backgroundShapeView.alphaValue = .zero
        overlayView.alphaValue = .zero
    }

    func layoutBackground() {
        if backgroundShapeView.frame != bounds {
            backgroundShapeView.frame = bounds
        }

        guard let layer = backgroundShapeView.layer else {
            assertionFailure()
            return
        }

        let anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if layer.anchorPoint != anchorPoint {
            layer.anchorPoint = anchorPoint
        }

        let position = CGPoint(x: bounds.midX, y: bounds.midY)
        if layer.position != position {
            layer.position = position
        }
    }

    func layoutOverlay() {
        let overlayFrame = bounds.inset(by: Metrics.overlayInsets)
        if overlayView.frame != overlayFrame {
            overlayView.frame = overlayFrame
        }
    }
}

// MARK: - State Machine Management

extension TabBackgroundView {

    func refreshStateIfNeeded(isSelected: Bool, isDragged: Bool, isMouseOver: Bool, animated: Bool = true) {
        let newState = TabBackgroundState.nextState(isMouseOver: isMouseOver, isSelected: isSelected, isDragged: isDragged)
        guard state != newState else {
            return
        }

        let animateExit = animated && !shouldSkipExitAnimation(from: state, to: newState)
        applyStateChange(state, entering: false, animated: animateExit)
        applyStateChange(newState, entering: true, animated: animated)
        state = newState
    }

    private func shouldSkipExitAnimation(from oldState: TabBackgroundState, to newState: TabBackgroundState) -> Bool {
        // Optimization: no need to animate Highlight dismissal when transitioning directly to Selected
        (oldState == .highlighted && newState == .selected)
    }

    private func applyStateChange(_ state: TabBackgroundState, entering: Bool, animated: Bool) {
        switch state {
        case .highlighted:
            refreshOverlayVisibility(entering, animated: animated)
        case .selected:
            refreshBackgroundVisibility(entering, animated: animated)
        case .dragged:
            backgroundShapeView.isDragged = entering
            refreshBackgroundVisibility(entering, animated: false)
        case .idle:
            break
        }
    }
}

// MARK: - Animations

private extension TabBackgroundView {

    func refreshOverlayVisibility(_ visible: Bool, animated: Bool) {
        guard let layer = overlayView.layer else {
            return
        }

        let toAlpha = visible ? Animations.overlayOpacityVisible : Animations.opacityHidden

        guard animated else {
            layer.removeAnimation(forKey: Animations.overlayKey)
            layer.opacity = toAlpha
            return
        }

        let fromAlpha = currentOpacity(of: layer)
        let animation = CABasicAnimation.buildFadeAnimation(duration: Animations.duration, fromAlpha: fromAlpha, toAlpha: toAlpha)

        layer.add(animation, forKey: Animations.overlayKey)
        layer.opacity = toAlpha
    }

    func refreshBackgroundVisibility(_ visible: Bool, animated: Bool) {
        guard let layer = backgroundShapeView.layer else {
            return
        }

        let toAlpha = visible ? Animations.opacityVisible : Animations.opacityHidden

        guard animated else {
            layer.removeAnimation(forKey: Animations.shapeKey)
            layer.opacity = toAlpha
            return
        }

        let duration = Animations.duration
        let fromAlpha = currentOpacity(of: layer)
        let fadeAnimation: CABasicAnimation = .buildFadeAnimation(duration: duration, fromAlpha: fromAlpha, toAlpha: toAlpha)

        let translationAnimation: CABasicAnimation = visible
            ? .buildTranslationYAnimation(duration: duration, fromValue: Animations.slideOffsetY, toValue: .zero)
            : .buildTranslationYAnimation(duration: duration, toValue: Animations.slideOffsetY)

        let scaleAnimation: CABasicAnimation = visible
            ? .buildScaleAnimation(duration: duration, fromValue: Animations.slideScaleDown, toValue: Animations.slideScaleFull)
            : .buildScaleAnimation(duration: duration, fromValue: Animations.slideScaleFull, toValue: Animations.slideScaleDown)

        let group = CAAnimationGroup()
        group.animations = [translationAnimation, fadeAnimation, scaleAnimation]
        group.duration = duration

        layer.add(group, forKey: Animations.shapeKey)
        layer.opacity = toAlpha
    }

    func currentOpacity(of layer: CALayer) -> Float {
        let isAnimated = layer.animationKeys() != nil
        let opacity = isAnimated ? layer.presentation()?.opacity : layer.opacity

        return opacity ?? layer.opacity
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
