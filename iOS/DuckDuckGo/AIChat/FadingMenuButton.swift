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

    /// Called once a fading menu has finished closing, when UIKit shows the button's glass again.
    var menuDidFadeOut: () -> Void = {}

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
        guard fadesMenuOnDismissal() else { return menuWillCloseInPlace() }
        menuWillFadeOut()
        guard let animator else { return menuDidFadeOut() }
        animator.addCompletion { [weak self] in self?.menuDidFadeOut() }
    }

    /// The button itself, so the menu shrinks back into it, or none, so it fades out.
    private var dismissalTarget: UITargetedPreview? {
        fadesMenuOnDismissal() ? nil : UITargetedPreview(view: self)
    }
}
