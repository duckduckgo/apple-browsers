//
//  NewTabPage.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// Content state used to hand off to and from the focused input.
protocol NewTabPageContentHandoff {

    /// Live visibility, including any override applied below.
    var isShowingLogo: Bool { get }
    var isShowingFavorites: Bool { get }

    /// Visibility ignoring the overrides, so a dismissal can pick its handoff while an
    /// override is still mid-transition.
    var restingContentIsLogo: Bool { get }
    var restingContentIsFavorites: Bool { get }

    /// Overrides visibility for the duration of a handoff.
    func setLogoHidden(_ hidden: Bool)
    func setFavoritesHidden(_ hidden: Bool)
}

protocol NewTabPageChromeAdapting {

    /// Suppression covers chrome that overlays the page surface, where the page's own framing
    /// border would show as an artifact against it.
    func setChromeLayoutContext(isBorderSuppressed: Bool)
}

/// The return-to-tab card shown after an idle period. A nil model means no card.
protocol NewTabPageEscapeHatchPresenting {

    func setEscapeHatch(_ model: EscapeHatchModel?)
}

/// Contextual onboarding and Duck.ai completion dialogs hosted over the New Tab Page.
protocol NewTabPageOnboardingPresenting {

    func showNextDaxDialog()

    /// Advances the dialog sequence at the end of linear onboarding.
    func onboardingCompleted()

    /// Presents over an active address bar editing session, which `textEntryMode` configures.
    func showDuckAIOnboardingCompletionWithActiveAddressBar(message: String, textEntryMode: TextEntryMode?)

    /// Re-runs the hosted dialog's top inset after the caller changes what sits above it.
    func refreshContextualOnboardingDialogLayout()

    /// Ending an address bar editing session is what dismisses the Duck.ai completion dialog.
    func dismissDuckAICompletionDialogIfNeededOnEditingEnd()
}

protocol NewTabPage: UIViewController,
                     HomeScreenTransitionSource,
                     NewTabPageContentHandoff,
                     NewTabPageChromeAdapting,
                     NewTabPageEscapeHatchPresenting,
                     NewTabPageOnboardingPresenting {

    var isDragging: Bool { get }

    var delegate: NewTabPageControllerDelegate? { get set }
    var chromeDelegate: BrowserChromeDelegate? { get set }

    /// Tears the page down and detaches it from its parent. Unrelated to
    /// `UIViewController.dismiss(animated:completion:)`.
    func dismiss()

    /// Width decides part of the page's framing, so a resize has to be pushed in rather than
    /// observed.
    func widthChanged()
}
