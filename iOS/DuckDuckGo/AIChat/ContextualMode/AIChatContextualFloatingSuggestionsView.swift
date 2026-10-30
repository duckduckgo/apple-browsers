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

    /// The column's input as the keyboard moves it, in the column's superview. It stays above the chips,
    /// so a chip passing under it is hidden rather than drawn over its text.
    struct InputEdge {
        let leading: CGFloat
        let fromTop: CGFloat
        let toTop: CGFloat
        /// UIKit's animation of the input's move, whose timing the edge copies so the two stay together.
        let motion: CABasicAnimation
    }

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
        /// The column's gap between its chips and the input, over which a chip passing under the input fades out.
        static let inputEdgeFade: CGFloat = 12
    }

    /// Show and hide run inside the keyboard's animation, which their own timing must not inherit.
    private static let ownTiming: UIView.AnimationOptions = [.overrideInheritedDuration, .overrideInheritedCurve, .overrideInheritedOptions]

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

    /// Hides the chips, and the page's dim with them, e.g. while the user types a prompt of their own.
    var isSteppedAside = false {
        didSet {
            guard isSteppedAside != oldValue else { return }
            alpha = isSteppedAside ? 0 : 1
            pageDimView.alpha = pageDimAlpha
        }
    }

    /// Dims the page under the chips, like the iPhone floating input. Purely visual: the page stays in use.
    private let pageDimView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()

    private var pageDimAlpha: CGFloat {
        isShown && !isSteppedAside ? ContextualSurfaceScrim.alpha : 0
    }

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
    /// The exact reverse of `hide(animated:to:under:completion:)`, so the stack leaves the way it comes back.
    func show(beside column: UIView, keyboardTop: CGFloat, from sourceFrames: [CGRect?], under input: InputEdge?) {
        guard let host = column.superview else { return }
        if superview !== host {
            removeFromSuperview()
            host.insertSubview(self, aboveSubview: column)
        }
        if pageDimView.superview !== host {
            pageDimView.removeFromSuperview()
            host.insertSubview(pageDimView, belowSubview: self)
        }
        self.column = column
        self.keyboardTop = keyboardTop
        isShown = true
        removeTakeoffStandIns()
        let chips = chipViews
        var standIns: [AIChatQuickActionChipView?] = []
        // The chips start where they take off, rather than animating there with the keyboard.
        UIView.performWithoutAnimation {
            isSteppedAside = false
            updateFrame()
            for (index, chip) in chips.enumerated() {
                chip.layer.removeAllAnimations()
                chip.alpha = 0
                guard index < actions.count, index < sourceFrames.count, let source = sourceFrames[index] else {
                    chip.transform = tuckedTransform
                    standIns.append(nil)
                    continue
                }
                // Exactly over its twin in the column, which hides as this appears, so the handover changes no pixel.
                let standIn = makeColumnStyleStandIn(for: actions[index], size: source.size)
                standIn.center = convert(CGPoint(x: source.midX, y: source.midY), from: host)
                chip.transform = transform(of: chip, ontoTitleOf: standIn, centeredAt: standIn.center)
                standIns.append(standIn)
            }
        }
        takeoffStandIns = standIns.compactMap { $0 }
        let inputCover = hideWhatPassesUnder(input, in: host)

        UIView.animate(withDuration: Constants.flightDuration,
                       delay: 0,
                       options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState, Self.ownTiming]) {
            self.pageDimView.alpha = self.pageDimAlpha
        }
        let takeoffs = DispatchGroup()
        for (index, chip) in chips.enumerated() {
            let delay = Double(index) * Constants.stagger
            guard let standIn = standIns[index] else {
                UIView.animate(withDuration: Constants.fadeDuration,
                               delay: delay,
                               options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState, Self.ownTiming]) {
                    chip.transform = .identity
                    chip.alpha = 1
                }
                continue
            }
            let cover = pose(of: standIn, coveringTitleOf: chip)
            takeoffs.enter()
            UIView.animate(withDuration: Constants.flightDuration,
                           delay: delay,
                           usingSpringWithDamping: Constants.flightDamping,
                           initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState, Self.ownTiming],
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
                           options: [.curveEaseInOut, .allowUserInteraction, Self.ownTiming]) {
                chip.alpha = 1
                standIn.alpha = 0
            }
        }
        let launched = takeoffStandIns
        takeoffs.notify(queue: .main) { [weak self] in
            guard let self, takeoffStandIns == launched else { return }
            removeTakeoffStandIns()
            if mask === inputCover {
                mask = nil
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
        // The page runs from the host's leading edge to the column, level with it.
        let hostBounds = column.superview?.bounds ?? .zero
        pageDimView.frame = CGRect(x: hostBounds.minX, y: columnFrame.minY,
                                   width: columnFrame.minX - hostBounds.minX, height: columnFrame.height)
    }

    /// Flies each chip back onto its twin's frame in `targetFrames` (in the column's superview), or fades it.
    /// `completion` runs once all have landed, when the column's own chips can take over.
    func hide(animated: Bool, to targetFrames: [CGRect] = [], under input: InputEdge? = nil, completion: (() -> Void)? = nil) {
        guard isShown else {
            completion?()
            return
        }
        isShown = false
        removeTakeoffStandIns()
        let chips = chipViews
        guard animated, !chips.isEmpty, let host = superview else {
            mask = nil
            removeFromSuperview()
            pageDimView.removeFromSuperview()
            pageDimView.alpha = 0
            completion?()
            return
        }
        hideWhatPassesUnder(input, in: host)
        UIView.animate(withDuration: Constants.flightDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, Self.ownTiming]) {
            self.pageDimView.alpha = 0
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
                               options: [.curveEaseIn, .beginFromCurrentState, Self.ownTiming],
                               animations: {
                                   chip.transform = self.tuckedTransform
                                   chip.alpha = 0
                               },
                               completion: landed)
                continue
            }
            let target = targetFrames[index]
            let standIn = makeColumnStyleStandIn(for: actions[index], size: target.size)
            let cover = pose(of: standIn, coveringTitleOf: chip)
            // Outside the keyboard's animation, which this is often called from: the copy starts on the glass chip.
            UIView.performWithoutAnimation {
                standIn.center = cover.center
                standIn.transform = cover.transform
                standIn.alpha = 0
            }
            standIns.append(standIn)
            let landing = convert(CGPoint(x: target.midX, y: target.midY), from: host)
            let chipLanding = transform(of: chip, ontoTitleOf: standIn, centeredAt: landing)
            UIView.animate(withDuration: Constants.flightDuration,
                           delay: delay,
                           usingSpringWithDamping: Constants.flightDamping,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, Self.ownTiming],
                           animations: {
                               chip.transform = chipLanding
                               standIn.center = landing
                               standIn.transform = .identity
                           },
                           completion: landed)
            // The glass turns into the column's look on the way, so it lands as an exact copy of its twin.
            UIView.animate(withDuration: Constants.restyleDuration,
                           delay: delay + Constants.restyleDelay,
                           options: [.curveEaseInOut, Self.ownTiming]) {
                chip.alpha = 0
                standIn.alpha = 1
            }
        }
        landings.notify(queue: .main) { [weak self] in
            completion?()
            // The column's chips now sit exactly under the stand-ins, so removing them changes no pixel.
            standIns.forEach { $0.removeFromSuperview() }
            guard let self, !isShown else { return }
            mask = nil
            removeFromSuperview()
            pageDimView.removeFromSuperview()
        }
    }

    /// Masks out whatever of the chips is under the input's top edge, moving that edge as the keyboard moves the input.
    @discardableResult
    private func hideWhatPassesUnder(_ input: InputEdge?, in host: UIView) -> UIView? {
        guard let input else {
            mask = nil
            return nil
        }
        let reach = convert(host.bounds, from: host).insetBy(dx: -host.bounds.width, dy: -host.bounds.height)
        let cover = UnderInputMask(frame: reach,
                                   inputLeading: convert(CGPoint(x: input.leading, y: 0), from: host).x,
                                   fade: Constants.inputEdgeFade)
        mask = cover
        cover.moveInputTop(from: convert(CGPoint(x: 0, y: input.fromTop), from: host).y,
                           to: convert(CGPoint(x: 0, y: input.toTop), from: host).y,
                           alongside: input.motion)
        return cover
    }

    /// A chip in the column's own style, sized like its twin in the column, for a glass chip to cross-fade with in flight.
    /// Built outside any animation in progress, such as the keyboard's, so its title doesn't grow in from nothing.
    private func makeColumnStyleStandIn(for action: ContextualSheetAction, size: CGSize) -> AIChatQuickActionChipView {
        let standIn = AIChatQuickActionChipView()
        UIView.performWithoutAnimation {
            standIn.configure(with: action)
            standIn.bounds = CGRect(origin: .zero, size: size)
            standIn.isUserInteractionEnabled = false
            addSubview(standIn)
            standIn.layoutIfNeeded()
        }
        return standIn
    }

    /// Where `standIn` sits, and how it scales, to lay its title exactly over `chip`'s at the chip's laid-out spot.
    /// The two styles differ in font and padding, so lining up their titles is what shows a single chip mid-fade.
    private func pose(of standIn: AIChatQuickActionChipView,
                      coveringTitleOf chip: AIChatQuickActionChipView) -> (center: CGPoint, transform: CGAffineTransform) {
        let chipCenter = chip.superview?.convert(chip.center, to: self) ?? chip.center
        let standInTitle = standIn.titleFrame
        guard standInTitle.width > 0 else { return (chipCenter, .identity) }
        let scale = chip.titleFrame.width / standInTitle.width
        let chipTitle = titleOffset(of: chip), standInTitleOffset = titleOffset(of: standIn)
        let center = CGPoint(x: chipCenter.x + chipTitle.dx - standInTitleOffset.dx * scale,
                             y: chipCenter.y + chipTitle.dy - standInTitleOffset.dy * scale)
        return (center, CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Lays `chip`'s title exactly over the title of `standIn` centred at `center`, wherever the chip sits now.
    /// Measured from `center` and `bounds`, which ignore the landing transform a chip keeps after flying home.
    private func transform(of chip: AIChatQuickActionChipView,
                           ontoTitleOf standIn: AIChatQuickActionChipView,
                           centeredAt center: CGPoint) -> CGAffineTransform {
        let chipTitleWidth = chip.titleFrame.width
        guard let container = chip.superview, chipTitleWidth > 0 else { return tuckedTransform }
        let scale = standIn.titleFrame.width / chipTitleWidth
        let chipCenter = container.convert(chip.center, to: self)
        let chipTitle = titleOffset(of: chip), standInTitle = titleOffset(of: standIn)
        return CGAffineTransform(translationX: center.x + standInTitle.dx - chipCenter.x - chipTitle.dx * scale,
                                 y: center.y + standInTitle.dy - chipCenter.y - chipTitle.dy * scale)
            .scaledBy(x: scale, y: scale)
    }

    private func titleOffset(of chip: AIChatQuickActionChipView) -> CGVector {
        let title = chip.titleFrame
        return CGVector(dx: title.midX - chip.bounds.midX, dy: title.midY - chip.bounds.midY)
    }

    private func removeTakeoffStandIns() {
        takeoffStandIns.forEach { $0.removeFromSuperview() }
        takeoffStandIns = []
    }

    private var chipViews: [AIChatQuickActionChipView] {
        chipsView.chipViews.filter { !$0.isHidden }
    }

    /// Nudged towards the column and slightly shrunk, for a chip arriving or leaving faded out.
    private var tuckedTransform: CGAffineTransform {
        CGAffineTransform(translationX: Constants.hiddenOffset, y: 0)
            .scaledBy(x: Constants.hiddenScale, y: Constants.hiddenScale)
    }
}

// MARK: - Under Input Mask

/// Shows everything but what lies under the input: right of its leading edge and below its top, fading in over `fade`
/// above the top so a chip slips under the card rather than being cut off by a line.
/// Animated with Core Animation: a mask is outside the window, where UIKit animates nothing.
private final class UnderInputMask: UIView {

    private let besideInput = CALayer()
    private let aboveInput = CAGradientLayer()

    init(frame: CGRect, inputLeading: CGFloat, fade: CGFloat) {
        super.init(frame: frame)
        besideInput.backgroundColor = UIColor.black.cgColor
        besideInput.frame = CGRect(x: 0, y: 0, width: max(0, inputLeading - frame.minX), height: frame.height)
        aboveInput.frame = CGRect(origin: .zero, size: frame.size)
        aboveInput.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor]
        aboveInput.locations = [0, NSNumber(value: Double(1 - fade / frame.height)), 1]
        layer.addSublayer(aboveInput)
        layer.addSublayer(besideInput)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Tops in the masked view's space. Moves the opaque part rather than resizing it, so the fade keeps its length.
    func moveInputTop(from start: CGFloat, to end: CGFloat, alongside motion: CABasicAnimation) {
        let startY = positionY(forInputTop: start), endY = positionY(forInputTop: end)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aboveInput.position.y = endY
        CATransaction.commit()
        guard startY != endY, let edge = motion.copy() as? CABasicAnimation else { return }
        // A copy keeps UIKit's delegate, which mustn't hear of an animation it didn't start.
        edge.delegate = nil
        edge.keyPath = "position.y"
        edge.isAdditive = false
        edge.fromValue = startY
        edge.toValue = endY
        edge.byValue = nil
        edge.isRemovedOnCompletion = true
        aboveInput.add(edge, forKey: "inputTop")
    }

    private func positionY(forInputTop top: CGFloat) -> CGFloat {
        top - frame.minY - aboveInput.bounds.height / 2
    }
}
