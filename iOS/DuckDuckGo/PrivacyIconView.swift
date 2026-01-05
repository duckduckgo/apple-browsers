//
//  PrivacyIconView.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Foundation
import UIKit
import Lottie
import DesignResourcesKit
import DesignResourcesKitIcons
import Kingfisher

// MARK: - Dax Easter Egg Logo Constants

private extension PrivacyIconView {
    /// Scale factor for dynamic Dax Easter Egg logos to match PDF default logo visual size (24/47 ≈ 0.51)
    static let daxLogoScaleFactor: CGFloat = 0.51
}

enum PrivacyIcon {
    case daxLogo, shield, shieldWithDot, alert

    fileprivate var staticImage: UIImage? {
        switch self {
        case .daxLogo: return UIImage(resource: .logoIcon)
        case .alert: return DesignSystemImages.Glyphs.Size24.alertRecolorable
        default: return nil
        }
    }
}

/// Delegate for handling privacy icon interactions.
protocol PrivacyIconViewDelegate: AnyObject {
    /// Called when user taps a Dax Easter Egg logo for full-screen presentation.
    func privacyIconViewDidTapDaxLogo(_ view: PrivacyIconView, logoURL: URL?, currentImage: UIImage?, sourceFrame: CGRect)
}

class PrivacyIconView: UIView {

    private(set) var staticImageView: UIImageView!
    private(set) var shieldAnimationView: LottieAnimationView!
    private(set) var shieldDotAnimationView: LottieAnimationView!
    private var transitionPlaceholderView: UIView!

    private(set) var icon: PrivacyIcon = .shield
    private(set) var daxLogoURL: URL?
    weak var delegate: PrivacyIconViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        // Allow animated views to overflow the 28x28 container
        clipsToBounds = false

        // Create static image view for Dax logo
        staticImageView = UIImageView(frame: bounds)
        staticImageView.translatesAutoresizingMaskIntoConstraints = false
        staticImageView.contentMode = .center
        addSubview(staticImageView)

        // Create shield animation views
        shieldAnimationView = LottieAnimationView(frame: bounds)
        shieldAnimationView.translatesAutoresizingMaskIntoConstraints = false
        shieldAnimationView.contentMode = .scaleAspectFit
        shieldAnimationView.backgroundBehavior = .pauseAndRestore
        shieldAnimationView.configuration = LottieConfiguration(renderingEngine: .mainThread)
        addSubview(shieldAnimationView)

        shieldDotAnimationView = LottieAnimationView(frame: bounds)
        shieldDotAnimationView.translatesAutoresizingMaskIntoConstraints = false
        shieldDotAnimationView.contentMode = .scaleAspectFit
        shieldDotAnimationView.backgroundBehavior = .pauseAndRestore
        shieldDotAnimationView.configuration = LottieConfiguration(renderingEngine: .mainThread)
        addSubview(shieldDotAnimationView)

        // Static image view for Dax logo and other images
        NSLayoutConstraint.activate([
            staticImageView.widthAnchor.constraint(equalToConstant: 47),
            staticImageView.heightAnchor.constraint(equalToConstant: 47),
            staticImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            staticImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Protections Enabled Animation
        NSLayoutConstraint.activate([
            shieldAnimationView.widthAnchor.constraint(equalToConstant: 47),
            shieldAnimationView.heightAnchor.constraint(equalToConstant: 47),
            shieldAnimationView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shieldAnimationView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Protextions Disable Animation
        NSLayoutConstraint.activate([
            shieldDotAnimationView.widthAnchor.constraint(equalToConstant: 44),
            shieldDotAnimationView.heightAnchor.constraint(equalToConstant: 44),
            shieldDotAnimationView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shieldDotAnimationView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        transitionPlaceholderView = UIView()
        transitionPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        transitionPlaceholderView.backgroundColor = UIColor(designSystemColor: .surface)
        transitionPlaceholderView.layer.cornerRadius = 12
        transitionPlaceholderView.isHidden = true
        addSubview(transitionPlaceholderView)

        NSLayoutConstraint.activate([
            transitionPlaceholderView.widthAnchor.constraint(equalToConstant: 24),
            transitionPlaceholderView.heightAnchor.constraint(equalToConstant: 24),
            transitionPlaceholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            transitionPlaceholderView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Add pointer interaction
        addInteraction(UIPointerInteraction(delegate: self))

        // Add tap gesture for Dax logo easter eggs
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(daxLogoTapped))
        staticImageView.addGestureRecognizer(tapGesture)
        staticImageView.isUserInteractionEnabled = true

        // Load animations
        loadAnimations()

        // Update display
        updateShieldImageView(for: icon)
        updateAccessibilityLabels(for: icon)
    }
    
    func loadAnimations(animationCache cache: AnimationCacheProvider = DefaultAnimationCache.sharedCache) {
        let useDarkStyle = traitCollection.userInterfaceStyle == .dark

        let shieldAnimationName = "shield.new"
        let shieldDotAnimationName = (useDarkStyle ? "dark-shield-dot" : "shield-dot")

        let shieldAnimation = LottieAnimation.named(shieldAnimationName, animationCache: cache)
        shieldAnimationView.animation = shieldAnimation

        let shieldWithDotAnimation = LottieAnimation.named(shieldDotAnimationName, animationCache: cache)
        shieldDotAnimationView.animation = shieldWithDotAnimation
    }
    
    func updateIcon(_ newIcon: PrivacyIcon) {
        guard newIcon != icon else { return }
        icon = newIcon
        let shouldAnimateCustomLogo = newIcon == .daxLogo && daxLogoURL != nil
        updateShieldImageView(for: newIcon, animateCustomLogo: shouldAnimateCustomLogo)
        updateAccessibilityLabels(for: newIcon)
    }
    
    func setDaxEasterEggLogoURL(_ url: URL?, completion: (() -> Void)? = nil) {
        let oldURL = daxLogoURL

        // Exit early if URL hasn't changed
        guard oldURL != url else { return }

        daxLogoURL = url

        if icon == .daxLogo {
            // Only animate when switching logo types (dynamic ↔ default)
            let isChangingLogoType = (oldURL == nil) != (url == nil)

            if isChangingLogoType && staticImageView.image != nil {
                // Set the correct size properties for the destination before animation
                if url != nil {
                    // Going to dynamic: set final size properties first
                    staticImageView.contentMode = .scaleAspectFit
                    let scaleTransform = CGAffineTransform(scaleX: Self.daxLogoScaleFactor, y: Self.daxLogoScaleFactor)
                    staticImageView.transform = scaleTransform.translatedBy(x: -1, y: -1)
                    staticImageView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                } else {
                    // Going to default: set final size properties first
                    staticImageView.contentMode = .center
                    staticImageView.transform = .identity
                    staticImageView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                }

                // Now do pure crossfade with just image change
                UIView.transition(with: staticImageView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                    if let url = url {
                        self.staticImageView.kf.setImage(with: url, placeholder: PrivacyIcon.daxLogo.staticImage)
                    } else {
                        self.staticImageView.image = PrivacyIcon.daxLogo.staticImage
                    }
                }, completion: { _ in
                    if url != nil {
                        self.animatePopEffect()
                    }
                })
            } else if url != nil {
                // Custom to custom transition
                UIView.transition(with: staticImageView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                    self.staticImageView.kf.setImage(with: url, placeholder: PrivacyIcon.daxLogo.staticImage)
                }, completion: { _ in
                    self.animatePopEffect()
                })
            } else {
                updateShieldImageView(for: icon)
            }

            completion?()
        }
    }

    @objc private func daxLogoTapped() {
        // Only allow tapping on custom Dax Easter egg logos, not the default logo
        if icon == .daxLogo && !staticImageView.isHidden && daxLogoURL != nil {
            let currentImage = staticImageView.image
            let sourceFrame = staticImageView.convert(staticImageView.bounds, to: nil)
            delegate?.privacyIconViewDidTapDaxLogo(self, logoURL: daxLogoURL, currentImage: currentImage, sourceFrame: sourceFrame)
        }
    }

    private func updateShieldImageView(for icon: PrivacyIcon, animateCustomLogo: Bool = false) {
        transitionPlaceholderView.isHidden = true

        switch icon {
        case .daxLogo:
            staticImageView.isHidden = false
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = true

            if let url = daxLogoURL {
                // Dynamic images: use scaleAspectFit to maintain aspect ratio and fit in bounds
                staticImageView.contentMode = .scaleAspectFit

                // Apply scale + adjustment to match PDF logo positioning
                let scaleTransform = CGAffineTransform(scaleX: Self.daxLogoScaleFactor, y: Self.daxLogoScaleFactor)
                let adjustedTransform = scaleTransform.translatedBy(x: -1, y: -1)
                staticImageView.transform = adjustedTransform

                // Ensure the transform is applied from the center to prevent repositioning
                staticImageView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

                // Load original high-quality image for both display and full-screen
                staticImageView.kf.setImage(with: url, placeholder: icon.staticImage) { [weak self] _ in
                    if animateCustomLogo {
                        self?.animatePopEffect()
                    }
                }
            } else {
                // PDF image (24x24) doesn't need scaleAspectFit - use natural size
                staticImageView.contentMode = .center
                staticImageView.transform = .identity
                staticImageView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                staticImageView.image = icon.staticImage
            }
        case .alert:
            staticImageView.isHidden = false
            staticImageView.image = icon.staticImage
            staticImageView.contentMode = .center
            staticImageView.transform = .identity
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = true
        case .shield:
            staticImageView.isHidden = true
            shieldAnimationView.isHidden = false
            shieldDotAnimationView.isHidden = true

            // Set animated view to frame 1
            if let animation = shieldAnimationView.animation {
                let totalFrames = animation.endFrame - animation.startFrame
                shieldAnimationView.currentProgress = totalFrames > 0 ? 1.0 / totalFrames : 0.0
            }
        case .shieldWithDot:
            staticImageView.isHidden = true
            shieldAnimationView.isHidden = true
            shieldDotAnimationView.isHidden = false

            // Set to final frame (100%) to show completed shield with checkmark
            shieldDotAnimationView.currentProgress = 1.0
        }
    }
    
    private func updateAccessibilityLabels(for icon: PrivacyIcon) {
        switch icon {
        case .daxLogo:
            accessibilityLabel = UserText.privacyIconDax
            accessibilityHint = nil
            accessibilityTraits = .image
        case .shield, .shieldWithDot, .alert:
            accessibilityIdentifier = "privacy-icon-shield.button"
            shieldAnimationView.accessibilityIdentifier = "privacy-icon-shield.button"
            shieldDotAnimationView.accessibilityIdentifier = "privacy-icon-shield.button"
            accessibilityLabel = UserText.privacyIconShield
            accessibilityHint = UserText.privacyIconOpenDashboardHint
            accessibilityTraits = .button
        }
    }

    private func animatePopEffect() {
        let baseTransform = staticImageView.transform
        let angle: CGFloat = .pi / 10  // ~18 degrees

        UIView.animateKeyframes(withDuration: 0.6, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.15) {
                self.staticImageView.transform = baseTransform.rotated(by: angle)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.15, relativeDuration: 0.15) {
                self.staticImageView.transform = baseTransform.rotated(by: -angle)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.15) {
                self.staticImageView.transform = baseTransform.rotated(by: angle)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.15) {
                self.staticImageView.transform = baseTransform.rotated(by: -angle)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.2) {
                self.staticImageView.transform = baseTransform.rotated(by: angle * 0.4)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                self.staticImageView.transform = baseTransform
            }
        }
    }

    func refresh() {
        updateShieldImageView(for: icon)
        updateAccessibilityLabels(for: icon)
        // Keep animated views visible at frame 1 - do NOT hide them
    }

    /// Hides the static image view during full-screen transition to avoid duplicate logos.
    func hideLogoForTransition() {
        staticImageView.isHidden = true
        transitionPlaceholderView.isHidden = false
    }

    /// Shows the static image view after full-screen transition completes.
    func showLogoAfterTransition() {
        transitionPlaceholderView.isHidden = true
        if icon == .daxLogo || icon == .alert {
            staticImageView.isHidden = false
        }
    }
    
    func prepareForAnimation(for icon: PrivacyIcon) {
        let showDot = (icon == .shieldWithDot)
        shieldAnimationView.isHidden = showDot
        shieldDotAnimationView.isHidden = !showDot
        staticImageView.isHidden = true
    }

    func shieldAnimationView(for icon: PrivacyIcon) -> LottieAnimationView? {
        switch icon {
        case .shield:
            return shieldAnimationView
        case .shieldWithDot:
            return shieldDotAnimationView
        case .daxLogo, .alert:
            return nil
        }
    }
    
    var isAnimationPlaying: Bool {
        shieldAnimationView.isAnimationPlaying || shieldDotAnimationView.isAnimationPlaying
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            loadAnimations()
        }
    }
}

extension PrivacyIconView: UIPointerInteractionDelegate {
    
    public func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // Don't treat Dax logo as a button
        if icon == .daxLogo {
            return nil
        }
        return UIPointerStyle(effect: .automatic(.init(view: self)), shape: .roundedRect(frame, radius: 12))
    }
    
}
