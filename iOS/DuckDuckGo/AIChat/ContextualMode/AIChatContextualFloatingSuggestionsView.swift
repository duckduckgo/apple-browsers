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
        static let fadeDuration: TimeInterval = 0.24
        static let flightDuration: TimeInterval = 0.5
        static let flightDamping: CGFloat = 1
        static let restyleDuration: TimeInterval = 0.3
        static let restyleDelay: TimeInterval = 0.08
        static let stagger: TimeInterval = 0.035
        static let dimmedAlpha: CGFloat = 0.4
    }

    var onActionSelected: ((ContextualSheetAction) -> Void)? {
        get { chipsView.onActionSelected }
        set { chipsView.onActionSelected = newValue }
    }

    private(set) var isShown = false
    private var actions: [ContextualSheetAction] = []
    private weak var column: UIView?
    private var keyboardTop: CGFloat = 0
    /// The column-style copies the chips take off from, until the glass has taken over.
    private var takeoffStandIns: [UIView] = []

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
        self.actions = actions
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

    /// Places the chips beside `column`, just above `keyboardTop` (in the column's superview), flying each one out
    /// from the matching frame in `sourceFrames`; chips without one fade in from the column's edge.
    /// The exact reverse of `hide(animated:to:completion:)`, so the stack leaves the way it comes back.
    func show(beside column: UIView, keyboardTop: CGFloat, from sourceFrames: [CGRect]) {
        guard let host = column.superview else { return }
        if superview !== host {
            removeFromSuperview()
            host.insertSubview(self, aboveSubview: column)
        }
        self.column = column
        self.keyboardTop = keyboardTop
        isShown = true
        removeTakeoffStandIns()
        let chips = chipViews
        var standIns: [UIView?] = []
        // Outside the keyboard's animation, which this is often called from: the chips start where they take off.
        UIView.performWithoutAnimation {
            updateFrame()
            for (index, chip) in chips.enumerated() {
                chip.layer.removeAllAnimations()
                chip.alpha = 0
                guard index < sourceFrames.count, index < actions.count else {
                    chip.transform = tuckedTransform
                    standIns.append(nil)
                    continue
                }
                chip.transform = transform(from: sourceFrames[index], to: chip, in: host)
                // Exactly over its twin in the column, which hides as this appears, so the handover changes no pixel.
                let source = convert(sourceFrames[index], from: host)
                let standIn = makeColumnStyleStandIn(for: actions[index])
                standIn.center = CGPoint(x: source.midX, y: source.midY)
                standIns.append(standIn)
            }
        }
        let chipStandIns = standIns
        takeoffStandIns = standIns.compactMap { $0 }
        // A pass later, once that start is on screen; a view added in this pass has nothing to animate from.
        DispatchQueue.main.async { [weak self] in
            guard let self, isShown else { return }
            let takeoffs = DispatchGroup()
            for (index, chip) in chips.enumerated() {
                let delay = Double(index) * Constants.stagger
                guard let standIn = chipStandIns[index] else {
                    UIView.animate(withDuration: Constants.fadeDuration,
                                   delay: delay,
                                   options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                        chip.transform = .identity
                        chip.alpha = 1
                    }
                    continue
                }
                let cover = covering(chip, with: standIn)
                takeoffs.enter()
                UIView.animate(withDuration: Constants.flightDuration,
                               delay: delay,
                               usingSpringWithDamping: Constants.flightDamping,
                               initialSpringVelocity: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState],
                               animations: {
                                   chip.transform = .identity
                                   standIn.center = cover.center
                                   standIn.transform = cover.transform
                               },
                               completion: { _ in takeoffs.leave() })
                // The column's look turns into the glass on the way, timed as the reverse of the trip home.
                let restyleDelay = Constants.flightDuration - Constants.restyleDelay - Constants.restyleDuration
                UIView.animate(withDuration: Constants.restyleDuration,
                               delay: delay + restyleDelay,
                               options: [.curveEaseInOut, .allowUserInteraction]) {
                    chip.alpha = 1
                    standIn.alpha = 0
                }
            }
            let launched = takeoffStandIns
            takeoffs.notify(queue: .main) { [weak self] in
                guard let self, takeoffStandIns == launched else { return }
                removeTakeoffStandIns()
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

    /// Flies each chip back onto its twin's frame in `targetFrames` (in the column's superview), or fades it.
    /// `completion` runs once all have landed, when the column's own chips can take over.
    func hide(animated: Bool, to targetFrames: [CGRect] = [], completion: (() -> Void)? = nil) {
        guard isShown else {
            completion?()
            return
        }
        isShown = false
        removeTakeoffStandIns()
        let chips = chipViews
        guard animated, !chips.isEmpty, let host = superview else {
            removeFromSuperview()
            completion?()
            return
        }

        // Every chip has to land before the handover: they land in reverse order, so no single one marks the end.
        let landings = DispatchGroup()
        var standIns: [UIView] = []
        for (index, chip) in chips.enumerated() {
            // Last chip out is first back, so the stack unwinds the way it built.
            let delay = Double(chips.count - 1 - index) * Constants.stagger
            landings.enter()
            let landed: (Bool) -> Void = { _ in landings.leave() }
            guard index < targetFrames.count, index < actions.count else {
                UIView.animate(withDuration: Constants.fadeDuration,
                               delay: delay,
                               options: [.curveEaseIn, .beginFromCurrentState],
                               animations: {
                                   chip.transform = self.tuckedTransform
                                   chip.alpha = 0
                               },
                               completion: landed)
                continue
            }
            let target = convert(targetFrames[index], from: host)
            let standIn = makeColumnStyleStandIn(for: actions[index])
            let cover = covering(chip, with: standIn)
            standIn.center = cover.center
            standIn.transform = cover.transform
            standIn.alpha = 0
            standIns.append(standIn)
            UIView.animate(withDuration: Constants.flightDuration,
                           delay: delay,
                           usingSpringWithDamping: Constants.flightDamping,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState],
                           animations: {
                               chip.transform = self.transform(from: targetFrames[index], to: chip, in: host)
                               standIn.center = CGPoint(x: target.midX, y: target.midY)
                               standIn.transform = .identity
                           },
                           completion: landed)
            // The glass turns into the column's look on the way, so it lands as an exact copy of its twin.
            UIView.animate(withDuration: Constants.restyleDuration, delay: delay + Constants.restyleDelay, options: [.curveEaseInOut]) {
                chip.alpha = 0
                standIn.alpha = 1
            }
        }
        landings.notify(queue: .main) { [weak self] in
            completion?()
            // The column's chips now sit exactly under the stand-ins, so removing them changes no pixel.
            standIns.forEach { $0.removeFromSuperview() }
            guard let self, !isShown else { return }
            removeFromSuperview()
        }
    }

    /// A chip in the column's own style, at its natural size, for a glass chip to cross-fade with in flight.
    private func makeColumnStyleStandIn(for action: ContextualSheetAction) -> UIView {
        let standIn = AIChatQuickActionChipView()
        standIn.configure(with: action)
        standIn.bounds = CGRect(origin: .zero, size: standIn.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
        standIn.isUserInteractionEnabled = false
        addSubview(standIn)
        return standIn
    }

    /// Where `standIn` sits, and how it scales, to cover `chip` at its laid-out spot, whatever transform the chip has.
    private func covering(_ chip: UIView, with standIn: UIView) -> (center: CGPoint, transform: CGAffineTransform) {
        let center = chip.superview?.convert(chip.center, to: self) ?? chip.center
        let scale = standIn.bounds.width > 0 ? chip.bounds.width / standIn.bounds.width : 1
        return (center, CGAffineTransform(scaleX: scale, y: scale))
    }

    private func removeTakeoffStandIns() {
        takeoffStandIns.forEach { $0.removeFromSuperview() }
        takeoffStandIns = []
    }

    private var chipViews: [UIView] {
        chipsView.chipViews.filter { !$0.isHidden }
    }

    /// Nudged towards the column and slightly shrunk, for a chip arriving or leaving faded out.
    private var tuckedTransform: CGAffineTransform {
        CGAffineTransform(translationX: Constants.hiddenOffset, y: 0)
            .scaledBy(x: Constants.hiddenScale, y: Constants.hiddenScale)
    }

    /// Maps `chip` at its laid-out frame onto `source`. Measured from `center` and `bounds`, which ignore the
    /// landing transform a chip keeps after flying home; `convert(_:to:)` would fold it into the target.
    private func transform(from source: CGRect, to chip: UIView, in host: UIView) -> CGAffineTransform {
        guard let container = chip.superview else { return tuckedTransform }
        let center = container.convert(chip.center, to: host)
        let size = chip.bounds.size
        let target = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        guard target.width > 0, target.height > 0 else { return tuckedTransform }
        // By width, so the larger glass text lines up with its twin's as it lands.
        let scale = source.width / target.width
        return CGAffineTransform(translationX: source.midX - target.midX, y: source.midY - target.midY)
            .scaledBy(x: scale, y: scale)
    }
}
