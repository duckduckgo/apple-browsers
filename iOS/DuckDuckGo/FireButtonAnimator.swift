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

    case fireRising
    case waterSwirl
    case airstream
    case none
    
    var id: String { self.rawValue }
    
    var descriptionText: String {
        switch self {
        case .fireRising:
            return UserText.fireButtonAnimationFireRisingName
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
        case .fireRising:
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
    /// | Animation   | FPS | Frames | Base Duration | Speed | Actual Duration |
    /// |-------------|-----|--------|---------------|-------|-----------------|
    /// | Fire        | 30  | 35     | 1.17s         | 1.0   | 1.17s           |
    /// | Water Swirl | 12  | 24     | 2.00s         | 1.3   | 1.54s           |
    /// | Airstream   | 12  | 18     | 1.50s         | 1.3   | 1.15s           |
    ///
    /// Note: Fire uses a lower speed multiplier (1.0 vs 1.3) because it already has
    /// a higher frame rate (30fps vs 12fps) and shorter base duration (1.17s vs 2.0s).
    /// Using 1.3 would make it run at 0.90s, which feels too fast compared to other animations.
    var speed: Double {
        switch self {
        case .fireRising:
            return 1.0
        case .waterSwirl, .airstream:
            return 1.3
        case .none:
            return 0
        }
    }
    
    private var fileName: String? {
        switch self {
        case .fireRising:
            return "01_Fire_rebranded"
        case .waterSwirl:
            return "02_Water_swirl_really_small"
        case .airstream:
            return "03_Airstream_divided_by_four"
        case .none:
            return nil
        }
    }

}

class FireButtonAnimator {
    
    private let appSettings: AppSettings
    private var preLoadedComposition: LottieAnimation?

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        reloadPreLoadedComposition()
                
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onFireButtonAnimationChange),
                                               name: AppUserDefaults.Notifications.currentFireButtonAnimationChange,
                                               object: nil)
    }
        
    func animate(onAnimationStart: @escaping () async -> Void, onTransitionCompleted: @escaping () async -> Void, completion: @escaping () async -> Void) {

        guard let window = UIApplication.shared.firstKeyWindow,
              let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            Task { @MainActor in
                await onAnimationStart()
                await onTransitionCompleted()
                await completion()
            }
            return
        }
        
        guard let composition = preLoadedComposition else {
            Task { @MainActor in
                await onAnimationStart()
                await onTransitionCompleted()
                await completion()
            }
            return
        }
        
        window.addSubview(snapshot)
        
        let animationView = LottieAnimationView(animation: composition)
        let currentAnimation = appSettings.currentFireButtonAnimation
        let speed = currentAnimation.speed
        animationView.contentMode = .scaleAspectFill
        animationView.animationSpeed = CGFloat(speed)
        animationView.frame = window.frame
        window.addSubview(animationView)

        let duration = Double(composition.duration) / speed
        let delay = duration * currentAnimation.transition
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            snapshot.removeFromSuperview()
            Task { @MainActor in
                await onTransitionCompleted()
            }
        }
        
        animationView.play(fromProgress: 0, toProgress: 1) { [weak animationView] _ in
            animationView?.removeFromSuperview()
            Task { @MainActor in
                await completion()
            }
        }

        DispatchQueue.main.async {
            Task { @MainActor in
                await onAnimationStart()
            }
        }
    }
    
    @objc func onFireButtonAnimationChange() {
        reloadPreLoadedComposition()
    }
    
    private func reloadPreLoadedComposition() {
        preLoadedComposition = appSettings.currentFireButtonAnimation.composition
    }
}
