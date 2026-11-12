//
//  FireButtonAnimator.swift
//  DuckDuckGo
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

import UIKit
import Lottie

enum FireButtonAnimationType: String, CaseIterable, Identifiable, CustomStringConvertible {
    
    var description: String {
        return descriptionText
    }

    case fireRising // New fire animation
    case fireRisingLegacy // Old fire animation
    case waterSwirl
    case airstream
    case none
    
    var id: String { self.rawValue }
    
    var descriptionText: String {
        switch self {
        case .fireRising:
            return UserText.fireButtonAnimationFireRisingName
        case .fireRisingLegacy:
            return UserText.fireButtonAnimationFireRisingLegacyName
        case .waterSwirl:
            return UserText.fireButtonAnimationWaterSwirlName
        case .airstream:
            return UserText.fireButtonAnimationAirstreamName
        case .none:
            return UserText.fireButtonAnimationNoneName
        }
    }
    
    var composition: LottieAnimation? {
        guard let fileName = fileName else { return nil }
        return LottieAnimation.named(fileName, animationCache: DefaultAnimationCache.sharedCache)
    }

    var transition: Double {
        switch self {
        case .fireRising, .fireRisingLegacy:
            return 0.35
        case .waterSwirl:
            return 0.5
        case .airstream:
            return 0.5
        case .none:
            return 0
        }
    }
    
    /// Animation playback speed multiplier.
    /// Each animation has different base characteristics (frame rate, frame count, duration),
    /// so speed is tuned per-animation to achieve consistent perceived timing.
    ///
    /// Animation Timing Reference:
    /// | Animation        | FPS | Frames | Base Duration | Speed | Actual Duration |
    /// |------------------|-----|--------|---------------|-------|-----------------|
    /// | Fire (new)       | 30  | 35     | 1.17s         | 1.0   | 1.17s           |
    /// | Fire (legacy)    | 12  | 24     | 2.00s         | 1.3   | 1.54s           |
    /// | Water Swirl      | 12  | 24     | 2.00s         | 1.3   | 1.54s           |
    /// | Airstream        | 12  | 18     | 1.50s         | 1.3   | 1.15s           |
    ///
    /// Note: The new Fire animation uses a lower speed multiplier (1.0 vs 1.3) because it has
    /// a higher frame rate (30fps vs 12fps) and shorter base duration (1.17s vs 2.0s).
    /// Using 1.3 would make it run at 0.90s, which feels too fast compared to other animations.
    var speed: Double {
        switch self {
        case .fireRising:
            return 1.0
        case .fireRisingLegacy, .waterSwirl, .airstream:
            return 1.3
        case .none:
            return 1.0 // Safety net to avoid division by 0 if preloading behaviour is ever refactored and 'Double(composition.duration) / speed' is executed.
        }
    }
    
    private var fileName: String? {
        switch self {
        case .fireRising:
            return "01_Fire_rebranded"
        case .fireRisingLegacy:
            return "01_Fire_really_small"
        case .waterSwirl:
            return "02_Water_swirl_really_small"
        case .airstream:
            return "03_Airstream_divided_by_four"
        case .none:
            return nil
        }
    }

}

@MainActor
class FireButtonAnimator {

    static let overlayIdentifier = "Browser.Window.FireAnimation"
    
    private let appSettings: AppSettings
    private var preLoadedComposition: LottieAnimation?
    private let preBurnSnapshots = NSHashTable<UIView>.weakObjects()

    init(appSettings: AppSettings, notificationCenter: NotificationCenter = .default) {
        self.appSettings = appSettings
        reloadPreLoadedComposition()
                
        notificationCenter.addObserver(self,
                                       selector: #selector(onFireButtonAnimationChange),
                                       name: AppUserDefaults.Notifications.currentFireButtonAnimationChange,
                                       object: nil)
        notificationCenter.addObserver(self,
                                       selector: #selector(onApplicationWillResignActive),
                                       name: UIApplication.willResignActiveNotification,
                                       object: nil)
    }
        
    func animate(in windows: [UIWindow]? = nil,
                 instrumentation: FireAnimationInstrumentation? = nil,
                 onAnimationStart: @escaping () async -> Void,
                 onTransitionCompleted: @escaping () async -> Void,
                 completion: @escaping () async -> Void) {
        removePreBurnSnapshot()

        var seen: Set<ObjectIdentifier> = []
        let windows = (windows ?? [UIApplication.shared.firstKeyWindow].compactMap { $0 })
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
        let snapshots = windows.compactMap { window -> (UIWindow, UIView)? in
            guard let snapshot = window.snapshotView(afterScreenUpdates: false) else { return nil }
            return (window, snapshot)
        }
        guard let composition = preLoadedComposition, !snapshots.isEmpty else {
            Task { @MainActor in
                await onAnimationStart()
                await onTransitionCompleted()
                await completion()
            }
            return
        }
        
        let currentAnimation = appSettings.currentFireButtonAnimation
        let speed = currentAnimation.speed
        let animations = DispatchGroup()
        var allFinished = true

        for (window, snapshot) in snapshots {
            let overlay = UIView(frame: window.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.accessibilityIdentifier = Self.overlayIdentifier
            snapshot.frame = overlay.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(snapshot)
            preBurnSnapshots.add(snapshot)

            let animationView = LottieAnimationView(animation: composition)
            animationView.contentMode = .scaleAspectFill
            animationView.animationSpeed = CGFloat(speed)
            animationView.frame = overlay.bounds
            animationView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(animationView)
            window.addSubview(overlay)

            animations.enter()
            animationView.play(fromProgress: 0, toProgress: 1) { [weak overlay] finished in
                overlay?.removeFromSuperview()
                allFinished = allFinished && finished
                animations.leave()
            }
        }

        let duration = Double(composition.duration) / speed
        let delay = duration * currentAnimation.transition
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            snapshots.forEach { $0.1.removeFromSuperview() }
            Task { @MainActor in
                await onTransitionCompleted()
            }
        }
        
        animations.notify(queue: .main) {
            Task { @MainActor in
                if allFinished {
                    instrumentation?.animationDidFinish(animation: currentAnimation)
                }
                await completion()
            }
        }

        DispatchQueue.main.async {
            Task { @MainActor in
                await onAnimationStart()
            }
        }
    }

    private func removePreBurnSnapshot() {
        preBurnSnapshots.allObjects.forEach { $0.removeFromSuperview() }
        preBurnSnapshots.removeAllObjects()
    }
    
    @objc func onFireButtonAnimationChange() {
        reloadPreLoadedComposition()
    }

    @objc private func onApplicationWillResignActive() {
        removePreBurnSnapshot()
    }
    
    private func reloadPreLoadedComposition() {
        preLoadedComposition = appSettings.currentFireButtonAnimation.composition
    }
}
