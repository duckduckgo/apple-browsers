//
//  FireViewModel.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import FoundationExtensions
import BrowserServicesKit
import FeatureFlags_macOS
import os.log
import PrivacyConfig
import WebKit
import History

extension Fire.BurningData {
    /**
     * We want to delay showing modal dialog by 1s while burn animation is being played
     * on the New Tab Page (i.e. when "specific domains" are burned without all-window fire animation).
     */
    func shouldDelayShowingDialog(decider: VisualizeFireSettingsDecider) -> Bool {
        switch self {
        case .specificDomains(_, false, _):
            return decider.shouldShowFireAnimation
        default:
            return false
        }
    }

    /// Text of the modal dialog shown while data is being deleted.
    ///
    /// With the simplified Fire Dialog it describes the scope of the burn for a single tab burn
    /// and for an all-data burn, and stays generic for all other burns. Without the simplified
    /// Fire Dialog it always stays generic.
    func deletingDataMessage(featureFlagger: FeatureFlagger) -> String {
        guard featureFlagger.isFeatureOn(.fireDialogSimplified) else {
            return UserText.fireDialogDeletingData
        }

        switch self {
        case .all, .specificDomains(_, _, .allWindows):
            return UserText.fireDialogDeletingAllData
        case .specificDomains(_, _, .tab):
            return UserText.fireDialogDeletingDataFromThisTab
        case .specificDomains:
            return UserText.fireDialogDeletingData
        }
    }
}

final class FireViewModel {

    let fire: FireProtocol

    /// Whether either fire animation is on screen.
    @Published private(set) var isAnimationPlaying = false

    /// Only the burn animation takes part in the burn's dispatch group. With one shared flag a closing
    /// Fire Window's animation could swallow its stop edge, leaving the burn waiting on a `leave()`.
    private var isBurnAnimationPlaying = false
    private var isFireWindowAnimationPlaying = false

    private enum Animation: Hashable {
        case burn
        case fireWindow
    }

    private let animationTimeout: TimeInterval
    private var animationTimeouts = [Animation: DispatchWorkItem]()

    func setAnimationPlaying(_ isAnimationPlaying: Bool, isFireWindow: Bool) {
        if isFireWindow {
            if isFireWindowAnimationPlaying != isAnimationPlaying {
                isFireWindowAnimationPlaying = isAnimationPlaying
                resetTimeout(for: .fireWindow, isPlaying: isAnimationPlaying)
            }
        } else if isBurnAnimationPlaying != isAnimationPlaying {
            isBurnAnimationPlaying = isAnimationPlaying
            resetTimeout(for: .burn, isPlaying: isAnimationPlaying)

            if isAnimationPlaying {
                fire.fireAnimationDidStart()
            } else {
                fire.fireAnimationDidFinish()
            }
        }

        let isAnyAnimationPlaying = isBurnAnimationPlaying || isFireWindowAnimationPlaying
        guard self.isAnimationPlaying != isAnyAnimationPlaying else { return }
        self.isAnimationPlaying = isAnyAnimationPlaying
    }

    /// The animation's completion callback dies with the window the burn may close. Reporting the stop
    /// edge ourselves is what keeps a lost callback from leaving the overlay up, and the animation
    /// unable to play again, for the rest of the session.
    private func resetTimeout(for animation: Animation, isPlaying: Bool) {
        animationTimeouts.removeValue(forKey: animation)?.cancel()
        guard isPlaying else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Logger.fire.error("Fire animation never reported finishing")
            self?.setAnimationPlaying(false, isFireWindow: animation == .fireWindow)
        }
        animationTimeouts[animation] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + animationTimeout, execute: workItem)
    }

    /// Publisher that emits true if burning animation or burning process is in progress
    var isFirePresentationInProgress: AnyPublisher<Bool, Never> {
        Publishers
            .CombineLatest($isAnimationPlaying.removeDuplicates(), fire.burningDataPublisher.removeDuplicates())
            .map { (isAnimationPlaying, burningData) in
                let shouldDisplayDialog = isAnimationPlaying || burningData != nil
                if burningData?.shouldDelayShowingDialog(decider: self.fire.visualizeFireAnimationDecider) == true {
                    return Just(shouldDisplayDialog).delay(for: .seconds(1), scheduler: RunLoop.main).eraseToAnyPublisher()
                }
                return Just(shouldDisplayDialog).eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    @MainActor
    init(fire: FireProtocol, animationTimeout: TimeInterval = .seconds(4)) {
        self.fire = fire
        self.animationTimeout = animationTimeout
    }

    @MainActor
    init(tld: TLD, visualizeFireAnimationDecider: VisualizeFireSettingsDecider, animationTimeout: TimeInterval = .seconds(4)) {
        fire = Fire(tld: tld, visualizeFireAnimationDecider: visualizeFireAnimationDecider)
        self.animationTimeout = animationTimeout
    }

    var isBurning: Bool {
        return fire.burningData != nil
    }

}
