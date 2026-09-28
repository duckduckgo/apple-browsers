//
//  BrowserChromeButton.swift
//  DuckDuckGo
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

import UIKit
import os.log
import ObjectiveC
import DesignResourcesKit
import DesignResourcesKitIcons
import SitePermissions

class BrowserChromeButton: UIButton {

    /// UIKit reparents this into the menu platter, so callers inside a glass group pass a throwaway.
    var menuHighlightTarget: (() -> UIView?)?

    @available(iOS 16.0, *)
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configuration: UIContextMenuConfiguration,
                                         highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        targetedMenuPreview()
    }

    @available(iOS 16.0, *)
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configuration: UIContextMenuConfiguration,
                                         dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        targetedMenuPreview()
    }

    private func targetedMenuPreview() -> UITargetedPreview? {
        guard let target = menuHighlightTarget?() else { return nil }
        return UITargetedPreview(view: target)
    }

    enum ButtonType {
        case primary
        case secondary
        case tabSwitcher
        case toolbar
    }

    var type: ButtonType {
        didSet {
            applyConfiguration()
        }
    }

    // For debugging in memory graph.
    class BrowserChromeButtonBorder: UIView { }
    private weak var border: BrowserChromeButtonBorder?

    init(_ type: ButtonType = .primary) {
        self.type = type
        super.init(frame: .zero)

        applyConfiguration(animated: false)
    }
    
    required init?(coder: NSCoder) {
        self.type = .primary
        super.init(coder: coder)

        applyConfiguration(animated: false)
    }

    func addBorder(borderFrame: CGRect = CGRect(x: 0, y: 0, width: 80, height: 40)) {
        automaticallyUpdatesConfiguration = false
        guard border == nil else { return }
        let view = BrowserChromeButtonBorder(frame: borderFrame)
        view.center = self.center
        view.layer.borderWidth = 1.5
        view.layer.cornerRadius = 14
        view.backgroundColor = .clear
        border = view
        addSubview(view)
        applyConfiguration(animated: false)
        setNeedsDisplay()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let border {
            let converted = convert(point, to: border)
            return border.hitTest(converted, with: event) ?? super.hitTest(point, with: event)
        }

        return super.hitTest(point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        border?.backgroundColor = type.backgroundColor(for: .highlighted)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        border?.backgroundColor = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        border?.backgroundColor = nil
    }

    func removeBorder() {
        automaticallyUpdatesConfiguration = true
        guard let border else { return }
        border.removeFromSuperview()
        applyConfiguration(animated: false)
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        border?.center = center
    }

    func setImage(_ image: UIImage?) {
        configuration?.image = image
    }

    var hasImage: Bool {
        configuration?.image != nil
    }

    var hasTitle: Bool {
        !(configuration?.title?.isEmpty ?? true) || !(currentTitle?.isEmpty ?? true)
    }

    override func setNeedsDisplay() {
        border?.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        super.setNeedsDisplay()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
            setNeedsDisplay()
        }
    }

    func applyConfiguration(animated: Bool = true) {
        let image = configuration?.image
        let defaultConfiguration = defaultConfiguration()

        configuration = defaultConfiguration

        let type = self.type

        configuration?.image = image
        configuration?.automaticallyUpdateForSelection = false
        configuration?.imageColorTransformer = .init { [weak self] _ in
                type.foregroundColor(for: self?.state ?? .normal)
        }

        configurationUpdateHandler = { button in
            var newConfiguration = button.configuration ?? defaultConfiguration
            newConfiguration.baseForegroundColor = type.foregroundColor(for: button.state)
            newConfiguration.baseBackgroundColor = type.backgroundColor(for: button.state)
            if animated {
                UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
                    button.configuration = newConfiguration
                }.startAnimation()
            } else {
                button.configuration = newConfiguration
            }
        }
    }

    private func defaultConfiguration() -> UIButton.Configuration {
        switch type {
        case .primary, .secondary:
            return .omniBarDefault()
        case .tabSwitcher:
            return .tabSwitcherDefault()
        case .toolbar:
            return .toolbarGlyph()
        }
    }
}

private extension BrowserChromeButton.ButtonType {

    func backgroundColor(for state: UIButton.State) -> UIColor {

        switch state {
        case .highlighted:
            return UIColor(designSystemColor: .controlsFillPrimary)
        default:
            return .clear
        }
    }

    func foregroundColor(for state: UIButton.State) -> UIColor {

        switch self {
        case .primary:
            switch state {
            case .disabled:
                return UIColor(designSystemColor: .icons).withAlphaComponent(0.5)
            default:
                return UIColor(designSystemColor: .icons)
            }
        case .secondary, .tabSwitcher:
            switch state {
            case .disabled:
                return UIColor(designSystemColor: .iconsSecondary).withAlphaComponent(0.5)
            default:
                return UIColor(designSystemColor: .iconsSecondary)
            }

        case .toolbar:
            switch state {
            case .disabled:
                return UIColor(singleUseColor: SingleUseColor.toolbarButton).withAlphaComponent(0.5)
            default:
                return UIColor(singleUseColor: SingleUseColor.toolbarButton)
            }
        }
    }
}

private extension UIButton.Configuration {
    static func omniBarDefault() -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .dynamic
        config.buttonSize = .medium
        config.titleAlignment = .center
        config.background.backgroundInsets = .init(top: 2, leading: 2, bottom: 2, trailing: 2)

        config.background.cornerRadius = 14

        return config
    }

    static func toolbarGlyph() -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.titleAlignment = .center
        return config
    }

    static func tabSwitcherDefault() -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .dynamic
        config.buttonSize = .medium
        config.titleAlignment = .center
        config.background.backgroundInsets = .init(top: 4, leading: 4, bottom: 4, trailing: 4)

        config.background.cornerRadius = 8

        return config
    }

}

extension BrowserChromeButton {

    static let toolbarButtonSize: CGFloat = 44

    static func createToolbarButton(title: String, image: UIImage?, fixedWidth: CGFloat? = toolbarButtonSize, action: (() -> Void)? = nil) -> BrowserChromeButton {
        let button = BrowserChromeButton(.toolbar)
        if let image {
            button.setImage(image)
        } else {
            // Text buttons (no icon) render `title` as their visible label; icon buttons use it only for accessibility.
            button.setTitle(title, for: .normal)
        }

        if let action {
            button.addAction(UIAction { _ in
                action()
            }, for: .touchUpInside)
        }

        button.accessibilityLabel = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: toolbarButtonSize).isActive = true
        // Icon buttons use a fixed width; text buttons pass nil and size to their title (see applyTextConstraints).
        if let fixedWidth {
            button.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        }

        return button
    }

    static func createToolbarButtonItem(title: String, image: UIImage?, fixedWidth: CGFloat? = toolbarButtonSize, action: (() -> Void)? = nil) -> UIBarButtonItem {
        let button = createToolbarButton(title: title, image: image, fixedWidth: fixedWidth, action: action)

        let barItem = UIBarButtonItem(customView: button)

        if #available(iOS 26.0, *) {
            barItem.hidesSharedBackground = true
        }

        barItem.title = title

        return barItem
    }

}

extension UIButton {

    func setMenuAlertVisible(_ isVisible: Bool, animated: Bool = true) {
        let state = menuAlertState
        let isChangingVisibility = state.isVisible != isVisible
        state.isVisible = isVisible
        cancelSitePermissionAnimation()
        state.cancelAnimation()
        setMenuAlertIconTransform(.identity)

        let updateIcon = {
            self.setMenuAlertImage(isVisible ? DesignSystemImages.Glyphs.Size24.menuHamburgerAlert : DesignSystemImages.Glyphs.Size24.menuHamburger)
            self.setMenuAlertDotHidden(!isVisible)
        }

        guard animated, isVisible, isChangingVisibility else {
            updateIcon()
            return
        }

        // Matches `TabSwitcherStaticButton.animateUpdate`.
        let shrinkAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeIn) {
            self.setMenuAlertIconTransform(CGAffineTransform(scaleX: 0.5, y: 0.5))
        }

        let expandAnimator = UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.3) {
            self.setMenuAlertIconTransform(.identity)
        }

        state.shrinkAnimator = shrinkAnimator
        state.expandAnimator = expandAnimator

        shrinkAnimator.addCompletion { [weak self, weak state] position in
            guard let self, let state, state.isVisible, position == .end else { return }
            updateIcon()
            self.setMenuAlertIconTransform(CGAffineTransform(scaleX: 0.5, y: 0.5))
            state.shrinkAnimator = nil
            expandAnimator.startAnimation()
        }

        expandAnimator.addCompletion { [weak state] _ in
            state?.expandAnimator = nil
        }

        shrinkAnimator.startAnimation()
    }

    func animateSitePermissionGranted(_ permissionTypes: [SitePermissionType], reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        cancelSitePermissionAnimation()
        guard let permissionType = permissionTypes.first else { return }
        // Account for each glyph's padding and proportions, using location as the visual size reference.
        let (image, badgeSize, horizontalOffset): (UIImage, CGFloat, CGFloat) = switch permissionType {
        case .camera: (DesignSystemImages.Glyphs.Size16.permissionCameraSolid, 15, 8)
        case .microphone: (DesignSystemImages.Glyphs.Size16.permissionMicrophoneSolid, 13, 6.5)
        case .location: (DesignSystemImages.Glyphs.Size16.locationSolid, 11, 6.5)
        }

        let state = menuAlertState
        state.cancelAnimation()
        setMenuAlertIconTransform(.identity)
        setMenuAlertImage(DesignSystemImages.Glyphs.Size24.menuHamburger)
        setMenuAlertDotHidden(true)
        layoutIfNeeded()
        guard let menuImageView = imageView else { return }

        let badge = UIImageView(image: image)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isUserInteractionEnabled = false
        badge.accessibilityElementsHidden = true
        badge.tintColor = UIColor(designSystemColor: .buttonsDeleteGhostText)
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: menuImageView.centerXAnchor, constant: horizontalOffset),
            badge.centerYAnchor.constraint(equalTo: menuImageView.centerYAnchor, constant: 4),
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
        ])
        layoutIfNeeded()
        state.permissionBadge = badge

        let mask = CAShapeLayer()
        mask.frame = menuImageView.bounds
        menuImageView.layer.mask = mask
        state.permissionMask = mask
        setPermissionMenuBars(shortened: true, duration: reduceMotion ? 0 : 0.15)

        badge.alpha = 0
        badge.transform = reduceMotion ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
        let entrance = UIViewPropertyAnimator(duration: reduceMotion ? 0.15 : 0.45, dampingRatio: 0.35) {
            badge.alpha = 1
            badge.transform = .identity
        }
        state.permissionAnimator = entrance
        entrance.startAnimation()

        let dismissal = DispatchWorkItem { [weak self, weak badge] in
            guard let self, let badge else { return }
            self.setPermissionMenuBars(shortened: false, duration: reduceMotion ? 0 : 0.15)
            let exit = UIViewPropertyAnimator(duration: 0.15, curve: .easeOut) {
                badge.alpha = 0
            }
            exit.addCompletion { [weak self] position in
                guard let self, position == .end else { return }
                self.cancelSitePermissionAnimation()
                if permissionTypes.count > 1 {
                    self.animateSitePermissionGranted(Array(permissionTypes.dropFirst()), reduceMotion: reduceMotion)
                }
            }
            self.menuAlertState.permissionAnimator = exit
            exit.startAnimation()
        }
        state.permissionDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.95, execute: dismissal)
    }

    func cancelSitePermissionAnimation() {
        let state = menuAlertState
        guard let badge = state.permissionBadge else { return }
        state.permissionDismissal?.cancel()
        state.permissionDismissal = nil
        state.permissionAnimator?.stopAnimation(true)
        state.permissionAnimator = nil
        imageView?.layer.mask = nil
        state.permissionMask = nil
        badge.removeFromSuperview()
        state.permissionBadge = nil
        setMenuAlertImage(state.isVisible ? DesignSystemImages.Glyphs.Size24.menuHamburgerAlert : DesignSystemImages.Glyphs.Size24.menuHamburger)
        setMenuAlertDotHidden(!state.isVisible)
    }

    private func setPermissionMenuBars(shortened: Bool, duration: TimeInterval) {
        guard let mask = menuAlertState.permissionMask else { return }
        // Mask the existing 24 pt glyph so its top bar and left edges stay fixed.
        func path(shortened: Bool) -> CGPath {
            let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 24, height: 8))
            for y: CGFloat in [11, 17.5] {
                path.append(UIBezierPath(roundedRect: CGRect(x: 3, y: y, width: shortened ? 8 : 18, height: 1.5), cornerRadius: 0.75))
            }
            return path.cgPath
        }
        let newPath = path(shortened: shortened)
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = mask.presentation()?.path ?? mask.path ?? path(shortened: false)
        animation.toValue = newPath
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = newPath
        CATransaction.commit()
        if duration > 0 {
            mask.add(animation, forKey: "permissionMenuBars")
        }
    }

    private var menuAlertState: MenuAlertButtonState {
        if let state = objc_getAssociatedObject(self, &menuAlertButtonStateKey) as? MenuAlertButtonState {
            return state
        }

        let state = MenuAlertButtonState()
        objc_setAssociatedObject(self, &menuAlertButtonStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    private func setMenuAlertImage(_ image: UIImage?) {
        if let browserChromeButton = self as? BrowserChromeButton {
            browserChromeButton.setImage(image)
        } else if configuration != nil {
            configuration?.image = image
        } else {
            setImage(image, for: .normal)
        }
    }

    private func setMenuAlertDotHidden(_ hidden: Bool) {
        guard !hidden else {
            menuAlertDotImageViewIfPresent?.isHidden = true
            return
        }

        let dotImageView = menuAlertDotImageView()
        dotImageView.isHidden = false
        dotImageView.tintColor = UIColor(designSystemColor: .accentPrimary)
        bringSubviewToFront(dotImageView)
    }

    private func setMenuAlertIconTransform(_ transform: CGAffineTransform) {
        imageView?.transform = transform
        menuAlertDotImageViewIfPresent?.transform = transform
    }

    private var menuAlertDotImageViewIfPresent: UIImageView? {
        subviews.first { $0.tag == MenuAlertMetrics.dotViewTag } as? UIImageView
    }

    private func menuAlertDotImageView() -> UIImageView {
        if let menuAlertDotImageView = menuAlertDotImageViewIfPresent {
            return menuAlertDotImageView
        }

        let imageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.menuHamburgerAlertDot)
        imageView.tag = MenuAlertMetrics.dotViewTag
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        imageView.tintColor = UIColor(designSystemColor: .accentPrimary)
        imageView.accessibilityElementsHidden = true

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: MenuAlertMetrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: MenuAlertMetrics.iconSize),
        ])

        return imageView
    }
}

private enum MenuAlertMetrics {
    static let dotViewTag = 0xDDBA7
    static let iconSize: CGFloat = 24
}

private var menuAlertButtonStateKey: UInt8 = 0

private final class MenuAlertButtonState {
    var isVisible = false
    var shrinkAnimator: UIViewPropertyAnimator?
    var expandAnimator: UIViewPropertyAnimator?
    var permissionBadge: UIImageView?
    var permissionMask: CAShapeLayer?
    var permissionAnimator: UIViewPropertyAnimator?
    var permissionDismissal: DispatchWorkItem?

    func cancelAnimation() {
        shrinkAnimator?.stopAnimation(true)
        expandAnimator?.stopAnimation(true)
        shrinkAnimator = nil
        expandAnimator = nil
    }
}
