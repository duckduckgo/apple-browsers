//
//  AIChatContextualFloatingSuggestionsView.swift
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
import UIKit

/// The sidebar's suggestions lifted onto the page beside it, in the iPhone floating input's glass.
/// Each chip flies out from where its twin sat in the column, so the list visibly leaves the sidebar.
final class AIChatContextualFloatingSuggestionsView: UIView {

    private enum Constants {
        static let columnSpacing: CGFloat = 16
        static let keyboardSpacing: CGFloat = 16
        static let edgeInset: CGFloat = 16
        static let hiddenScale: CGFloat = 0.9
        static let hiddenOffset: CGFloat = 40
        static let showDuration: TimeInterval = 0.62
        static let showDamping: CGFloat = 0.8
        static let hideDuration: TimeInterval = 0.24
        static let returnDuration: TimeInterval = 0.5
        static let returnDamping: CGFloat = 0.9
        static let stagger: TimeInterval = 0.035
        static let dimmedAlpha: CGFloat = 0.4
    }

    var onActionSelected: ((ContextualSheetAction) -> Void)? {
        get { chipsView.onActionSelected }
        set { chipsView.onActionSelected = newValue }
    }

    private(set) var isShown = false
    private weak var column: UIView?
    private var keyboardTop: CGFloat = 0

    private let chipsView: AIChatQuickActionsView<ContextualSheetAction> = {
        let view = AIChatQuickActionsView<ContextualSheetAction>()
        view.chipBackgroundStyle = .glass
        view.chipAlignment = .trailing
        // Interactive glass scales a chip past its bounds on touch.
        view.clipsToBounds = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(chipsView)
        NSLayoutConstraint.activate([
            chipsView.topAnchor.constraint(equalTo: topAnchor),
            chipsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chipsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chipsView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with actions: [ContextualSheetAction]) {
        chipsView.configure(with: actions)
        updateFrame()
    }

    func setLoading(_ isLoading: Bool) {
        chipsView.setLoading(isLoading)
        updateFrame()
    }

    func setDimmed(_ dimmed: Bool) {
        chipsView.alpha = dimmed ? Constants.dimmedAlpha : 1
        chipsView.isUserInteractionEnabled = !dimmed
    }

    /// Taps between and around the chips reach the page underneath.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        chipsView.containsChip(at: point, from: self)
    }

    /// Places the chips beside `column`, just above `keyboardTop` (in the column's superview), flying each one in
    /// from the matching frame in `sourceFrames`; chips without one slide in from the column's edge.
    func show(beside column: UIView, keyboardTop: CGFloat, from sourceFrames: [CGRect]) {
        guard let host = column.superview else { return }
        if superview !== host {
            removeFromSuperview()
            host.insertSubview(self, aboveSubview: column)
        }
        self.column = column
        self.keyboardTop = keyboardTop
        isShown = true
        let chips = chipViews
        // Outside the keyboard's animation, which this is often called from: the chips start where they take off.
        UIView.performWithoutAnimation {
            updateFrame()
            for (index, chip) in chips.enumerated() {
                chip.layer.removeAllAnimations()
                let isFromColumn = index < sourceFrames.count
                chip.transform = isFromColumn ? transform(from: sourceFrames[index], to: chip, in: host) : tuckedTransform
                chip.alpha = isFromColumn ? 1 : 0
            }
        }
        // A pass later, once that start is on screen; a view added in this pass has nothing to animate from.
        DispatchQueue.main.async { [weak self] in
            guard let self, isShown else { return }
            for (index, chip) in chips.enumerated() {
                UIView.animate(withDuration: Constants.showDuration,
                               delay: Double(index) * Constants.stagger,
                               usingSpringWithDamping: Constants.showDamping,
                               initialSpringVelocity: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    chip.transform = .identity
                    chip.alpha = 1
                }
            }
        }
    }

    /// Follows a keyboard that changes height while the chips are out, e.g. on rotation.
    func moveAbove(keyboardTop: CGFloat, animation: (duration: TimeInterval, options: UIView.AnimationOptions)) {
        guard isShown else { return }
        self.keyboardTop = keyboardTop
        UIView.animate(withDuration: animation.duration, delay: 0, options: animation.options) {
            self.updateFrame()
        }
    }

    /// Framed by hand rather than constrained: laying out the host here would snap the sidebar to its
    /// keyboard-up layout ahead of the keyboard's own animation.
    private func updateFrame() {
        guard isShown, let column, column.superview === superview else { return }
        let columnFrame = column.frame
        let size = chipsView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let width = min(size.width, columnFrame.minX - Constants.columnSpacing - Constants.edgeInset)
        let bottom = keyboardTop - Constants.keyboardSpacing
        let top = max(columnFrame.minY + Constants.edgeInset, bottom - size.height)
        frame = CGRect(x: columnFrame.minX - Constants.columnSpacing - width, y: top, width: width, height: size.height)
        layoutIfNeeded()
    }

    /// Slides the chips back towards the column as they fade, then leaves the view hierarchy.
    /// Flies each chip back onto the matching frame in `targetFrames` (in the column's superview), where its twin
    /// rests once the keyboard is down; chips without one fade towards the column. `completion` runs as they land.
    func hide(animated: Bool, to targetFrames: [CGRect] = [], completion: (() -> Void)? = nil) {
        guard isShown else {
            completion?()
            return
        }
        isShown = false
        let chips = chipViews
        guard animated, !chips.isEmpty, let host = superview else {
            removeFromSuperview()
            completion?()
            return
        }

        for (index, chip) in chips.enumerated() {
            let isToColumn = index < targetFrames.count
            let landing = isToColumn ? transform(from: targetFrames[index], to: chip, in: host) : tuckedTransform
            let changes = {
                chip.transform = landing
                chip.alpha = isToColumn ? 1 : 0
            }
            let landed: (Bool) -> Void = { [weak self] _ in
                guard index == chips.count - 1 else { return }
                if let self, !self.isShown {
                    self.removeFromSuperview()
                }
                completion?()
            }
            // Last chip out is first back, so the stack unwinds the way it built.
            let delay = Double(chips.count - 1 - index) * Constants.stagger
            if isToColumn {
                UIView.animate(withDuration: Constants.returnDuration,
                               delay: delay,
                               usingSpringWithDamping: Constants.returnDamping,
                               initialSpringVelocity: 0,
                               options: [.beginFromCurrentState],
                               animations: changes,
                               completion: landed)
            } else {
                UIView.animate(withDuration: Constants.hideDuration,
                               delay: delay,
                               options: [.curveEaseIn, .beginFromCurrentState],
                               animations: changes,
                               completion: landed)
            }
        }
    }

    private var chipViews: [UIView] {
        chipsView.chipViews.filter { !$0.isHidden }
    }

    /// Nudged towards the column and slightly shrunk, for a chip arriving or leaving faded out.
    private var tuckedTransform: CGAffineTransform {
        CGAffineTransform(translationX: Constants.hiddenOffset, y: 0)
            .scaledBy(x: Constants.hiddenScale, y: Constants.hiddenScale)
    }

    /// Maps `chip` at its laid-out frame onto `source`, so it can start out where its twin was drawn.
    private func transform(from source: CGRect, to chip: UIView, in host: UIView) -> CGAffineTransform {
        let target = chip.convert(chip.bounds, to: host)
        guard target.width > 0, target.height > 0 else { return tuckedTransform }
        let scale = source.height / target.height
        return CGAffineTransform(translationX: source.midX - target.midX, y: source.midY - target.midY)
            .scaledBy(x: scale, y: scale)
    }
}
