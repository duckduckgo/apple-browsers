//
//  OnboardingIntroViewModel.swift
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

import Foundation
import Core
import Onboarding
import class UIKit.UIApplication

@MainActor
final class OnboardingIntroViewModel: ObservableObject {
    @Published private(set) var state: OnboardingView.ViewState = .landing

    let copy: Copy
    var onCompletingOnboardingIntro: (() -> Void)?
    private var introSteps: [OnboardingIntroStep]

    private let defaultBrowserManager: DefaultBrowserManaging
    private let pixelReporter: LinearOnboardingPixelReporting
    private let onboardingManager: OnboardingManaging
    private let isIpad: Bool
    private let urlOpener: URLOpener
    private let appIconProvider: () -> AppIcon
    private let addressBarPositionProvider: () -> AddressBarPosition

    convenience init(pixelReporter: LinearOnboardingPixelReporting) {
        self.init(
            defaultBrowserManager: DefaultBrowserManager(),
            pixelReporter: pixelReporter,
            onboardingManager: OnboardingManager(),
            isIpad: UIDevice.current.userInterfaceIdiom == .pad,
            urlOpener: UIApplication.shared,
            appIconProvider: { AppIconManager.shared.appIcon },
            addressBarPositionProvider: { AppUserDefaults().currentAddressBarPosition }
        )
    }

    init(
        defaultBrowserManager: DefaultBrowserManaging,
        pixelReporter: LinearOnboardingPixelReporting,
        onboardingManager: OnboardingManaging,
        isIpad: Bool,
        urlOpener: URLOpener,
        appIconProvider: @escaping () -> AppIcon,
        addressBarPositionProvider: @escaping () -> AddressBarPosition
    ) {
        self.defaultBrowserManager = defaultBrowserManager
        self.pixelReporter = pixelReporter
        self.onboardingManager = onboardingManager
        self.isIpad = isIpad
        self.urlOpener = urlOpener
        self.appIconProvider = appIconProvider
        self.addressBarPositionProvider = addressBarPositionProvider

        introSteps = isIpad ? OnboardingIntroStep.defaultIPadFlow : OnboardingIntroStep.defaultIPhoneFlow
        copy = .default
    }

    func onAppear() {
        state = makeViewState(for: .introDialog)
        pixelReporter.measureOnboardingIntroImpression()
    }

    func startOnboardingAction() {
        state = makeViewState(for: .browserComparison)
        pixelReporter.measureBrowserComparisonImpression()
    }

    func setDefaultBrowserAction() {
        let urlPath = onboardingManager.settingsURLPath

        if let url = URL(string: urlPath) {
            urlOpener.open(url)
        }
        pixelReporter.measureChooseBrowserCTAAction()

        handleSetDefaultBrowserAction()
    }

    func cancelSetDefaultBrowserAction() {
        handleSetDefaultBrowserAction()
    }

    func addToDockContinueAction(isShowingAddToDockTutorial: Bool) {
        state = makeViewState(for: .appIconSelection)
        if isShowingAddToDockTutorial {
            pixelReporter.measureAddToDockTutorialDismissCTAAction()
        } else {
            pixelReporter.measureAddToDockPromoDismissCTAAction()
        }
    }

    func addtoDockShowTutorialAction() {
        pixelReporter.measureAddToDockPromoShowTutorialCTAAction()
    }

    func appIconPickerContinueAction() {
        // Check if user set DDG as default browser.
        measureDDGDefaultBrowserIfNeeded()

        if appIconProvider() != .defaultAppIcon {
            pixelReporter.measureChooseCustomAppIconColor()
        }

        if isIpad {
            onCompletingOnboardingIntro?()
        } else {
            state = makeViewState(for: .addressBarPositionSelection)
            pixelReporter.measureAddressBarPositionSelectionImpression()
        }
    }

    func selectAddressBarPositionAction() {
        if addressBarPositionProvider() == .bottom {
            pixelReporter.measureChooseBottomAddressBarPosition()
        }
        onCompletingOnboardingIntro?()
    }

#if DEBUG || ALPHA
    public func overrideOnboardingCompleted() {
        LaunchOptionsHandler().overrideOnboardingCompleted()
        onCompletingOnboardingIntro?()
    }
#endif
}

// MARK: - Private

private extension OnboardingIntroViewModel {

    func makeViewState(for introStep: OnboardingIntroStep) -> OnboardingView.ViewState {
        
        func stepInfo() -> OnboardingView.ViewState.Intro.StepInfo {
            guard let currentStepIndex = introSteps.firstIndex(of: introStep) else { return .hidden }

            // Remove startOnboardingDialog from the count of total steps since we don't show the progress for that step.
            return OnboardingView.ViewState.Intro.StepInfo(currentStep: currentStepIndex, totalSteps: introSteps.count - 1)
        }

        let viewState = switch introStep {
        case .introDialog:
            OnboardingView.ViewState.onboarding(.init(type: .startOnboardingDialog, step: .hidden))
        case .browserComparison:
            OnboardingView.ViewState.onboarding(.init(type: .browsersComparisonDialog, step: stepInfo()))
        case .addToDockPromo:
            OnboardingView.ViewState.onboarding(.init(type: .addToDockPromoDialog, step: stepInfo()))
        case .appIconSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAppIconDialog, step: stepInfo()))
        case .addressBarPositionSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAddressBarPositionDialog, step: stepInfo()))
        }

        return viewState
    }

    func handleSetDefaultBrowserAction() {
        if introSteps.contains(.addToDockPromo) {
            state = makeViewState(for: .addToDockPromo)
            pixelReporter.measureAddToDockPromoImpression()
        } else {
            state = makeViewState(for: .appIconSelection)
            pixelReporter.measureChooseAppIconImpression()
        }
    }

    func measureDDGDefaultBrowserIfNeeded() {
        guard onboardingManager.isEnrolledInSetAsDefaultBrowserExperiment else { return }

        defaultBrowserManager.defaultBrowserInfo()
            .onNewValue { newInfo in
                if newInfo.isDefaultBrowser {
                    pixelReporter.measureDidSetDDGAsDefaultBrowser()
                } else {
                    pixelReporter.measureDidNotSetDDGAsDefaultBrowser()
                }
            }
    }

}

// MARK: - OnboardingIntroStep

private enum OnboardingIntroStep {
    case introDialog
    case browserComparison
    case appIconSelection
    case addressBarPositionSelection
    case addToDockPromo

    static let defaultIPhoneFlow: [OnboardingIntroStep] = [.introDialog, .browserComparison, .addToDockPromo, .appIconSelection, .addressBarPositionSelection]
    static let defaultIPadFlow: [OnboardingIntroStep] = [.introDialog, .browserComparison, .appIconSelection]
}
