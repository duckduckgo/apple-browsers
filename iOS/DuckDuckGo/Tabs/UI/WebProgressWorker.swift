//
//  WebProgressWorker.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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

class WebProgressWorker {

    /// What the bar shows. Each call names its activity, and calls from an activity that doesn't own the bar are ignored.
    enum Activity {
        /// Driven by WebKit's rough estimate. Takes the bar over from a translation, which the navigation has cancelled.
        case pageLoad
        /// Driven by an exact fraction, so the bar fills as reported. Waits for a page load to finish.
        case translation
    }

    private struct Constants {
        static let initialProgress: CGFloat = 0.1
    }
    
    weak var progressBar: ProgressView? {
        didSet(oldValue) {
            oldValue?.hide()
            progressBar?.fillsLinearly = activity == .translation

            if isLoading {
                self.progressBar?.show(initialProgress: currentProgress)
            } else {
                self.progressBar?.hide()
            }
        }
    }
    
    /// Nil while the bar is hidden.
    private var activity: Activity?
    private var isLoading: Bool { activity != nil }
    private var currentProgress: CGFloat = 0.0
    
    func didStartLoading(_ activity: Activity = .pageLoad) {
        let pageLoadReplacesTranslation = self.activity == .translation && activity == .pageLoad
        guard !isLoading || pageLoadReplacesTranslation else { return }

        self.activity = activity
        currentProgress = 0
        progressBar?.fillsLinearly = activity == .translation
        progressBar?.show()
        progressBar?.increaseProgress(to: Constants.initialProgress, animated: true)
    }
    
    func progressDidChange(_ progress: Double, for activity: Activity = .pageLoad) {
        guard isLoading else { return }
        
        let progress = CGFloat(progress)
        guard progress > currentProgress else { return }
        currentProgress = progress
        
        progressBar?.increaseProgress(to: progress, animated: true)
    }
    
    func didFinishLoading(_ activity: Activity = .pageLoad) {
        guard isLoading else { return }
        self.activity = nil
        progressBar?.finishAndHide()
        currentProgress = 0
    }

    /// Hides the bar without filling it, so a stopped activity doesn't look finished.
    func didCancelLoading(_ activity: Activity) {
        guard self.activity == activity else { return }
        self.activity = nil
        progressBar?.hide()
        currentProgress = 0
    }
}
