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

    var isPresentingOnboardingDialog: Bool { get }

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

    /// Suppresses the chrome address bar while the page is not editing.
    var hasInlineSearchInput: Bool { get }

    var delegate: NewTabPageControllerDelegate? { get set }
    var chromeDelegate: BrowserChromeDelegate? { get set }

    /// Tears the page down and detaches it from its parent. Unrelated to
    /// `UIViewController.dismiss(animated:completion:)`.
    func dismiss()

    func widthChanged()
}

struct NewTabPageFocusedPose: Equatable {
    var inputOffset: CGFloat
    /// How far the greeting travels while it fades. It follows the input only when the input moves up the page.
    var greetingOffset: CGFloat
    var modulesOffset: CGFloat
    var showsModules: Bool
    var bottomInputHeight: CGFloat

    static let bottomInputModulesTopMargin: CGFloat = 8

    init(inputOffset: CGFloat, greetingOffset: CGFloat? = nil, modulesOffset: CGFloat, showsModules: Bool, bottomInputHeight: CGFloat = 0) {
        self.inputOffset = inputOffset
        self.greetingOffset = greetingOffset ?? inputOffset
        self.modulesOffset = modulesOffset
        self.showsModules = showsModules
        self.bottomInputHeight = bottomInputHeight
    }

    init(restingInputFrame: CGRect,
         focusedInputFrame: CGRect,
         cardPosition: UnifiedToggleInputCardPosition,
         safeAreaTop: CGFloat,
         bottomInputHeight: CGFloat = 0,
         showsModules: Bool) {
        switch cardPosition {
        case .top:
            self.init(inputOffset: focusedInputFrame.midY - restingInputFrame.midY,
                      modulesOffset: focusedInputFrame.maxY - restingInputFrame.maxY,
                      showsModules: showsModules)
        case .bottom:
            let modulesTop = safeAreaTop + Self.bottomInputModulesTopMargin
            self.init(inputOffset: focusedInputFrame.midY - restingInputFrame.midY,
                      greetingOffset: 0,
                      modulesOffset: modulesTop - restingInputFrame.maxY,
                      showsModules: showsModules,
                      bottomInputHeight: bottomInputHeight)
        }
    }

    var focusedInputRestingTransform: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: -inputOffset)
    }
}

protocol NewTabPageInputTransitionSource: AnyObject {
    /// The resting card's frame, without any focused pose transform.
    func searchInputTransitionFrame(in view: UIView) -> CGRect?
    /// The resting card's frame at the scroll offset editing began from, so a refreshed pose ignores scrolling while focused.
    func focusedPoseSearchInputFrame(in view: UIView) -> CGRect?
    func setSearchInputEditing(_ isEditing: Bool)
    var focusedPose: NewTabPageFocusedPose? { get }
    /// Moves the live blocks to the pose, or back to rest with nil. Call inside an animation to animate.
    /// Leaving a settled pose first returns the page to its resting scroll position, without animation.
    func setFocusedPose(_ pose: NewTabPageFocusedPose?)
    /// Lets the modules scroll beneath the focused input once it has arrived. Call outside any animation.
    func settleFocusedPose()
    func focusedModulesContain(_ point: CGPoint, in view: UIView) -> Bool
    /// Receives a horizontal flick that starts on the focused modules, which sit outside the focused layer's touch area.
    var onFocusedModeSwitchSwipe: ((TextEntryMode) -> Void)? { get set }
}
