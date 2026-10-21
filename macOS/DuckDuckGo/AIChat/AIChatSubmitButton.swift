//
//  AIChatSubmitButton.swift
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

import Cocoa
import DesignResourcesKit

/// Specialised submit button that participates in the omnibar's tab cycle when in voice
/// mode. In submit mode the textarea's Enter handles submission, so the button is skipped
/// in keyboard navigation; in voice mode there is no Enter shortcut on empty input, so users
/// need to be able to Tab onto this button and press Enter/Space to start the voice session.
///
/// Mirrors the keyboard handling in `AIChatOmnibarToolButton`: Tab calls a callback (so the
/// container VC can route focus back to the textarea), Enter/Space sends the button's action.
final class AIChatSubmitButton: MouseOverButton {

    private enum Constants {
        static let focusRingLineWidth: CGFloat = 1.5
        static let focusRingOutset: CGFloat = 1
    }

    private enum KeyCode {
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let returnKey: UInt16 = 36
    }

    /// Set by the container VC. When non-nil, `Tab` advances focus via this callback instead
    /// of the default first-responder chain.
    var onTabPressed: (() -> Void)?

    private let focusRingLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = Constants.focusRingLineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.isHidden = true
        return layer
    }()

    /// Stroke colour for the keyboard-focus ring; the container VC assigns it in `applyTheme(theme:)`.
    var focusRingColor: NSColor = NSColor(designSystemColor: .accentPrimary) {
        didSet { updateFocusRingStrokeColor() }
    }

    /// Mirrored onto the layer, which rounds the fill without clipping the focus ring outside the bounds.
    override var cornerRadius: CGFloat {
        didSet {
            layer?.cornerRadius = cornerRadius
            // Setting the layer's corner radius re-enables clipping.
            clipsToBounds = false
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupFocusRing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupFocusRing()
    }

    private func setupFocusRing() {
        wantsLayer = true
        // AppKit's native focus ring is always `controlAccentColor`, so draw our own.
        focusRingType = .none
        layer?.addSublayer(focusRingLayer)
        updateFocusRingStrokeColor()
    }

    private func updateFocusRingStrokeColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            focusRingLayer.strokeColor = focusRingColor.cgColor
        }
        CATransaction.commit()
    }

    private func setFocusRingHidden(_ hidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusRingLayer.isHidden = hidden
        CATransaction.commit()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { setFocusRingHidden(false) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { setFocusRingHidden(true) }
        return didResign
    }

    override func layout() {
        super.layout()
        // Focus ring sits just outside the button, matching `AIChatOmnibarToolButton`.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let outset = Constants.focusRingOutset
        focusRingLayer.frame = bounds.insetBy(dx: -outset, dy: -outset)
        focusRingLayer.path = CGPath(
            roundedRect: focusRingLayer.bounds,
            cornerWidth: cornerRadius + outset,
            cornerHeight: cornerRadius + outset,
            transform: nil
        )
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFocusRingStrokeColor()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.tab:
            if let onTabPressed {
                onTabPressed()
            } else {
                super.keyDown(with: event)
            }
        case KeyCode.space, KeyCode.returnKey:
            // NSButton's default keyDown doesn't reliably fire the action when the button
            // uses a custom layer-drawn appearance (`bezelStyle = .shadowlessSquare`, no border).
            if isEnabled, let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        default:
            super.keyDown(with: event)
        }
    }
}
