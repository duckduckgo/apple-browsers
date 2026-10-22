//
//  FireViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Cocoa
import Combine
import Common
import Lottie
import PrivacyConfig

/// Starts the presentation synchronously, before tab cleanup can change the captured window.
@MainActor
final class FireViewController: NSViewController {
    let fireViewModel: FireViewModel
    private let tabCollectionViewModel: TabCollectionViewModel
    @Published private(set) var isAnimatingInPlace = false
    private var inPlaceAnimation: LottieAnimationView?
    private var inPlaceAnimationLoadingTask: Task<LottieAnimationView?, Never>?
    private let visualizeFireAnimationDecider: VisualizeFireSettingsDecider
    private let featureFlagger: FeatureFlagger
    private var cancellable: AnyCancellable?

    static func create(tabCollectionViewModel: TabCollectionViewModel,
                       fireViewModel: FireViewModel,
                       visualizeFireAnimationDecider: VisualizeFireSettingsDecider,
                       featureFlagger: FeatureFlagger) -> FireViewController {
        FireViewController(tabCollectionViewModel: tabCollectionViewModel,
                           fireViewModel: fireViewModel,
                           visualizeFireAnimationDecider: visualizeFireAnimationDecider,
                           featureFlagger: featureFlagger)
    }

    private init(tabCollectionViewModel: TabCollectionViewModel,
                 fireViewModel: FireViewModel,
                 visualizeFireAnimationDecider: VisualizeFireSettingsDecider,
                 featureFlagger: FeatureFlagger) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.fireViewModel = fireViewModel
        self.visualizeFireAnimationDecider = visualizeFireAnimationDecider
        self.featureFlagger = featureFlagger
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("FireViewController: Bad initializer")
    }

    deinit {
        inPlaceAnimationLoadingTask?.cancel()
    }

    override func loadView() {
        view = ColorView(frame: .zero, backgroundColor: .clear, interceptClickEvents: true)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityIdentifier("FireViewController.burningOverlay")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if case .normal = AppVersion.runType {
            inPlaceAnimationLoadingTask = Task { await DefaultFireAnimationLoader.shared.createAnimationView() }
        }
        cancellable = fireViewModel.fire.burningDataPublisher.sink { [weak self] burningData in
            guard let self else { return }
            view.setAccessibilityLabel(burningData?.deletingDataMessage(featureFlagger: featureFlagger))
            view.superview?.isHidden = burningData == nil
            guard let burningData, let window = view.window,
                  window.windowController === Application.appDelegate.windowControllersManager.lastKeyMainWindowController,
                  !fireViewModel.isDataClearingAnimationPlaying,
                  fireViewModel.claimFirePresentation() else { return }

            let progress = FireProgressWindowController.present(
                fireViewModel: fireViewModel,
                message: burningData.deletingDataMessage(featureFlagger: featureFlagger),
                sourceWindow: window,
                delay: burningData.shouldDelayShowingDialog(decider: visualizeFireAnimationDecider) ? 1 : 0.3
            )
            guard burningData.shouldPlayFireAnimation(decider: visualizeFireAnimationDecider) else { return }
            if shouldAnimateInPlace(burningData: burningData) {
                animateInPlace(progress: progress)
                return
            }
            let presentation = FireWindowAnimationController(sourceWindow: window)
            fireViewModel.setAnimationPlaying(true, isFireWindow: false)
            presentation?.start { [fireViewModel] in
                fireViewModel.setAnimationPlaying(false, isFireWindow: false)
                progress.animationDidFinish()
            }
            if presentation == nil {
                fireViewModel.setAnimationPlaying(false, isFireWindow: false)
                progress.animationDidFinish()
            }
        }
    }

    /// Burns that preserve tabs use the live window. A pinned tab is replaced in place;
    /// the last regular tab can keep its window via a new tab.
    /// Other last-tab burns must still use the snapshot because their window closes.
    func shouldAnimateInPlace(burningData: Fire.BurningData) -> Bool {
        if case .specificDomains(_, closesTabs: false, scope: _) = burningData { return true }
        guard case .specificDomains(_, closesTabs: true, scope: .tab) = burningData else { return false }
        if tabCollectionViewModel.selectionIndex?.isPinnedTab == true
            || tabCollectionViewModel.tabCollection.tabs.count > 1 {
            return true
        }
        guard let windowController = view.window?.windowController as? MainWindowController else { return false }
        if !windowController.mainViewController.shouldCloseWindowWithoutRegularTabs {
            return true
        }
        return Application.appDelegate.windowControllersManager.mainWindowControllers.count == 1
            && fireViewModel.fire.shouldKeepWindowOpenWhenBurning(windowController)
    }

    private func animateInPlace(progress: FireProgressWindowController) {
        if let window = view.window {
            for child in window.childWindows ?? [] where child !== window.titlebarView?.window {
                child.close()
            }
        }
        // Reserve the burn's dispatch group before waiting for the animation asset to load.
        isAnimatingInPlace = true
        view.superview?.isHidden = false
        fireViewModel.setAnimationPlaying(true, isFireWindow: false)
        guard case .normal = AppVersion.runType else {
            finishInPlaceAnimation(progress: progress)
            return
        }
        Task { [weak self, fireViewModel] in
            let animation = await self?.inPlaceAnimationLoadingTask?.value
            guard let self else {
                fireViewModel.setAnimationPlaying(false, isFireWindow: false)
                progress.animationDidFinish()
                return
            }
            guard let animation else {
                finishInPlaceAnimation(progress: progress)
                return
            }
            if inPlaceAnimation == nil {
                animation.translatesAutoresizingMaskIntoConstraints = false
                animation.contentMode = .scaleToFill
                view.addSubview(animation)
                NSLayoutConstraint.activate([
                    animation.topAnchor.constraint(equalTo: view.topAnchor),
                    animation.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    animation.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    animation.trailingAnchor.constraint(equalTo: view.trailingAnchor)
                ])
                inPlaceAnimation = animation
            }
            animation.isHidden = false
            animation.currentProgress = 0
            animation.play(fromProgress: 0, toProgress: 1) { [weak self, fireViewModel] _ in
                if let self {
                    self.finishInPlaceAnimation(progress: progress)
                } else {
                    fireViewModel.setAnimationPlaying(false, isFireWindow: false)
                    progress.animationDidFinish()
                }
            }
        }
    }

    private func finishInPlaceAnimation(progress: FireProgressWindowController) {
        inPlaceAnimation?.isHidden = true
        isAnimatingInPlace = false
        fireViewModel.setAnimationPlaying(false, isFireWindow: false)
        progress.animationDidFinish()
    }

    /// The snapshot owns its lifetime, so closing the browser starts cleanup immediately.
    func animateFireWhenClosing(_ closeWindow: () -> Void) {
        guard visualizeFireAnimationDecider.shouldShowFireAnimation else {
            closeWindow()
            return
        }
        let presentation = view.window.flatMap {
            FireWindowAnimationController(sourceWindow: $0)
        }
        fireViewModel.setAnimationPlaying(true, isFireWindow: true)
        closeWindow()
        if let presentation {
            presentation.start { [fireViewModel] in
                fireViewModel.setAnimationPlaying(false, isFireWindow: true)
            }
        } else {
            fireViewModel.setAnimationPlaying(false, isFireWindow: true)
        }
    }
}
