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

    @IBOutlet var staticImageView: UIImageView!
    @IBOutlet var staticShieldAnimationView: LottieAnimationView!
    @IBOutlet var staticShieldDotAnimationView: LottieAnimationView!
    
    private(set) var daxLogoURL: URL?
    weak var delegate: PrivacyIconViewDelegate?
    

    @IBOutlet var shieldAnimationView: LottieAnimationView!
    @IBOutlet var shieldDotAnimationView: LottieAnimationView!

    public required init?(coder aDecoder: NSCoder) {
        icon = .shield
        super.init(coder: aDecoder)
        addInteraction(UIPointerInteraction(delegate: self))
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
  
        loadAnimations()
        
        updateShieldImageView(for: icon)
        updateAccessibilityLabels(for: icon)

        // Animations are not rendering properly when going back from background, hence the change.
        [staticShieldAnimationView,
         staticShieldDotAnimationView,
         shieldAnimationView,
         shieldDotAnimationView].forEach { animationView in
            animationView?.configuration = LottieConfiguration(renderingEngine: .mainThread)
        }
        
        // Add tap gesture for Dax logo
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(daxLogoTapped))
        staticImageView.addGestureRecognizer(tapGesture)
        staticImageView.isUserInteractionEnabled = true
    }
    
    func loadAnimations(animationCache cache: AnimationCacheProvider = DefaultAnimationCache.sharedCache) {
        let useDarkStyle = traitCollection.userInterfaceStyle == .dark

        let shieldAnimationName = (useDarkStyle ? "dark-shield" : "shield")
        let shieldDotAnimationName = (useDarkStyle ? "dark-shield-dot" : "shield-dot")

        let shieldAnimation = LottieAnimation.named(shieldAnimationName, animationCache: cache)

        shieldAnimationView.animation = shieldAnimation
        staticShieldAnimationView.animation = shieldAnimation
        staticShieldAnimationView.currentProgress = 0.0

        let shieldWithDotAnimation = LottieAnimation.named(shieldDotAnimationName, animationCache: cache)
        shieldDotAnimationView.animation = shieldWithDotAnimation
        staticShieldDotAnimationView.animation = shieldWithDotAnimation
        staticShieldDotAnimationView.currentProgress = 1.0
    }
    
    func updateIcon(_ newIcon: PrivacyIcon) {
        icon = newIcon
    }
    
    func setDaxEasterEggLogoURL(_ url: URL?) {
        daxLogoURL = url
        
        if icon == .daxLogo {
            updateShieldImageView(for: icon)
        }
    }
    
    @objc private func daxLogoTapped() {
        // Only allow tapping for dynamic logos, not the default Dax logo
        if icon == .daxLogo && !staticImageView.isHidden && daxLogoURL != nil {
            let currentImage = staticImageView.image
            let sourceFrame = staticImageView.convert(staticImageView.bounds, to: nil)
            delegate?.privacyIconViewDidTapDaxLogo(self, logoURL: daxLogoURL, currentImage: currentImage, sourceFrame: sourceFrame)
        }
    }
    
    
    private(set) var icon: PrivacyIcon {
        willSet {
            guard newValue != icon else { return }
            updateShieldImageView(for: newValue)
            updateAccessibilityLabels(for: newValue)
        }
    }
    
    private func updateShieldImageView(for icon: PrivacyIcon) {
        switch icon {
        case .daxLogo:
            staticImageView.isHidden = false
            staticShieldAnimationView.isHidden = true
            staticShieldDotAnimationView.isHidden = true
            
            if let url = daxLogoURL {
                // Dynamic images: use scaleAspectFit to fit in frame, then scale down more to match PDF
                staticImageView.contentMode = .scaleAspectFit
                
                // Apply a stronger transform since PDF has significant built-in padding
                let scale: CGFloat = 0.6 // Scale down to 60% to better match PDF's visual size
                staticImageView.transform = CGAffineTransform(scaleX: scale, y: scale)
                
                staticImageView.kf.setImage(with: url, placeholder: icon.staticImage) { _ in }
            } else {
                // PDF image (24x24) doesn't need scaleAspectFit - use natural size
                staticImageView.contentMode = .center
                staticImageView.transform = .identity // Reset any transform
                staticImageView.image = icon.staticImage
            }
        case .alert:
            staticImageView.isHidden = false
            staticImageView.image = icon.staticImage
            staticShieldAnimationView.isHidden = true
            staticShieldDotAnimationView.isHidden = true
        case .shield:
            staticImageView.isHidden = true
            staticShieldAnimationView.isHidden = false
            staticShieldDotAnimationView.isHidden = true
        case .shieldWithDot:
            staticImageView.isHidden = true
            staticShieldAnimationView.isHidden = true
            staticShieldDotAnimationView.isHidden = false
        }
    }
    
    private func updateAccessibilityLabels(for icon: PrivacyIcon) {
        switch icon {
        case .daxLogo:
            accessibilityLabel = UserText.privacyIconDax
            accessibilityHint = nil
            accessibilityTraits = .image
        case .shield, .shieldWithDot:
            accessibilityIdentifier = "privacy-icon-shield.button"
            accessibilityLabel = UserText.privacyIconShield
            accessibilityHint = UserText.privacyIconOpenDashboardHint
            accessibilityTraits = .button
        case .alert:
            accessibilityLabel = UserText.privacyIconShield
            accessibilityHint = UserText.privacyIconOpenDashboardHint
            accessibilityTraits = .button
        }
    }
    
    func refresh() {
        updateShieldImageView(for: icon)
        updateAccessibilityLabels(for: icon)
        shieldAnimationView.isHidden = true
        shieldDotAnimationView.isHidden = true
    }
    
    func prepareForAnimation(for icon: PrivacyIcon) {
        let showDot = (icon == .shieldWithDot)
        
        shieldAnimationView.isHidden = showDot
        shieldDotAnimationView.isHidden = !showDot

        staticShieldAnimationView.isHidden = true
        staticShieldDotAnimationView.isHidden = true
        staticImageView.isHidden = true
    }
    
    func shieldAnimationView(for icon: PrivacyIcon) -> LottieAnimationView? {
        switch icon {
        case .shield:
            return shieldAnimationView
        case .shieldWithDot:
            return shieldDotAnimationView
        default:
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

        // If the static image is visible then don't treat it like a button
        return !staticImageView.isHidden ? nil :
            UIPointerStyle(effect: .automatic(.init(view: self)), shape: .roundedRect(frame, radius: 12))
    }
    
}
