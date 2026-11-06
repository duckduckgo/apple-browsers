//
//  FadingMenuButton.swift
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

import UIKit
import os

private let debugLogger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "NewTabTransition")

/// A menu button whose menu can fade out in place instead of morphing back into it.
/// The morph hides the button until it lands, which a new tab growing over the page would show as a pop.
final class FadingMenuButton: UIButton {

    /// Asked as the menu closes, after the chosen item has run.
    var fadesMenuOnDismissal: () -> Bool = { false }

    /// Called as the menu opens.
    var menuWillOpen: () -> Void = {}

    /// Called as the menu closes without opening a new tab.
    var menuWillCloseInPlace: () -> Void = {}

    /// Called as a fading menu starts to close. UIKit still fades the button's glass back in afterwards,
    /// so a caller opening a new tab can cover the button here.
    var menuWillFadeOut: () -> Void = {}

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        dismissalTarget
    }

    @available(iOS 16.0, *)
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configuration: UIContextMenuConfiguration,
                                         dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        dismissalTarget
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        menuWillOpen()
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if fadesMenuOnDismissal() { menuWillFadeOut() } else { menuWillCloseInPlace() }
        debugLogger.debug("PILL menu willEnd at \(CACurrentMediaTime(), privacy: .public) animator=\(animator != nil, privacy: .public) \(self.pillState, privacy: .public)")
        // DEBUG: sample the glass while the dismissal runs.
        for delay in [0.05, 0.2, 0.4, 0.6] {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                debugLogger.debug("PILL glass +\(delay, privacy: .public)s: \(self?.glassAnimations ?? "-", privacy: .public) \(self?.pillState ?? "-", privacy: .public)")
            }
        }
        animator?.addCompletion { [weak self] in
            debugLogger.debug("PILL menu dismissal done at \(CACurrentMediaTime(), privacy: .public) \(self?.pillState ?? "-", privacy: .public)")
        }
    }

    /// Every animated layer in the pill's glass, two levels above the button.
    var glassAnimations: String {
        guard let glass = superview?.superview?.superview?.superview else { return "-" }
        var found: [String] = []
        func visit(_ layer: CALayer, depth: Int) {
            if let keys = layer.animationKeys(), !keys.isEmpty { found.append("\(depth):\(type(of: layer)):\(keys)") }
            layer.sublayers?.forEach { visit($0, depth: depth + 1) }
        }
        visit(glass.layer, depth: 0)
        return "\(type(of: glass)) \(found)"
    }

    private var pillState: String {
        let chain = sequence(first: self as UIView, next: { $0.superview }).prefix(5)
        let pill = chain.map { "\(type(of: $0)) a=\($0.alpha) h=\($0.isHidden) op=\($0.layer.opacity) lh=\($0.layer.isHidden) anims=\($0.layer.animationKeys() ?? [])" }.joined(separator: " > ")
        let overlays = window?.subviews.map { "\(type(of: $0)) h=\($0.isHidden)" } ?? []
        return pill + " | window: \(overlays)"
    }

    /// The button itself, so the menu shrinks back into it, or none, so it fades out.
    private var dismissalTarget: UITargetedPreview? {
        debugLogger.debug("PILL dismissal preview asked at \(CACurrentMediaTime(), privacy: .public) fades=\(self.fadesMenuOnDismissal(), privacy: .public) \(self.pillState, privacy: .public)")
        return fadesMenuOnDismissal() ? nil : UITargetedPreview(view: self)
    }
}
