//
//  OmniBarNotificationViewModel.swift
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

final class OmniBarNotificationViewModel: ObservableObject {

    enum Duration {
        static let notificationSlide: TimeInterval = 0.3
        static let iconAnimationDelay: TimeInterval = notificationSlide * 0.75
        static let notificationCloseDelay: TimeInterval = 1.75
        static let notificationFadeOutDelay: TimeInterval = notificationCloseDelay
        static let totalDuration: TimeInterval = 1.75
    }

    enum Parameters {
        static let startPercent: Double = 0.5
        static let stepsPerNumber: Int = 30
        static let steps: Int = 10
        static let rangeMultiplier: Int = 3
        static let easeOutCurve: Double = 4
    }

    let animationName: String
    let eventCount: Int
    private let textGenerator: ((Int) -> String)?

    @Published var text: String
    @Published var isOpen: Bool = false
    @Published var isAnimating: Bool = false

    init(text: String, animationName: String, eventCount: Int = 0, textGenerator: ((Int) -> String)? = nil) {
        self.animationName = animationName
        self.eventCount = eventCount
        self.textGenerator = textGenerator

        // Initialize with starting count (75% of total) if we have a count animation
        // Otherwise use the provided text
        if eventCount > 0, let generator = textGenerator {
            let startingCount = max(1, Int(ceil(Double(eventCount) * Parameters.startPercent)))
            self.text = generator(startingCount)
        } else {
            self.text = text
        }
    }
    
    func showNotification(completion: @escaping () -> Void) {
        // Open the notification
        self.isOpen = true

        // Start animation with a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + Duration.iconAnimationDelay) { [weak self] in
            guard let self = self else { return }
            self.isAnimating = true

            // If we have an event count, animate from 75% to 100% over 500ms with extreme easeOut
            // This needs to be done in the viewModel as the SwiftUI animation is flaky when updating the text
            // Optimized for small counts (< 25 trackers typical)
            if self.eventCount > 0 {
                // Capture base text for fallback case (legacy behavior)
                let baseText = self.textGenerator == nil ? self.text : ""

                let totalDuration: TimeInterval = Duration.totalDuration
                let startPercent = Parameters.startPercent

                // Calculate steps based on the range we're animating
                let animationRange = Int(ceil(Double(self.eventCount) * (1.0 - Parameters.startPercent)))
                // Use 3-4 steps per number for smooth progression
                let steps = max(Parameters.steps, min(animationRange * Parameters.rangeMultiplier, Parameters.stepsPerNumber))

                for i in 1...steps {
                    // Use linear timing for delays, but ease the count progression
                    let progress = Double(i) / Double(steps)
                    let delay = progress * totalDuration

                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self = self else { return }
                        let easedProgress = self.easeOut(progress)
                        // Interpolate from 75% to 100% of eventCount
                        let countProgress = startPercent + (easedProgress * (1.0 - startPercent))
                        let exactCount = Double(self.eventCount) * countProgress

                        // Use min() to ensure we show the final count on the last step
                        let currentCount = min(Int(floor(exactCount)), self.eventCount)

                        // Use textGenerator if available for proper localization, otherwise use simple concatenation
                        if let generator = self.textGenerator {
                            self.text = generator(currentCount)
                        } else {
                            // Fallback for legacy behavior
                            self.text = "\(currentCount) \(baseText)"
                        }
                    }
                }
            }
        }

        // Close the notification
        DispatchQueue.main.asyncAfter(deadline: .now() + Duration.notificationCloseDelay) { [weak self] in
            self?.isOpen = false
        }

        // Fire completion after everything
        DispatchQueue.main.asyncAfter(deadline: .now() + Duration.notificationFadeOutDelay) {
            completion()
        }
    }

    // Standard quartic easeOut curve (power of X)
    private func easeOut(_ t: Double) -> Double {
        return 1 - pow(1 - t, Parameters.easeOutCurve)
    }
}
