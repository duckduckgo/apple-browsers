//
//  BackgroundTaskManager.swift
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
import os.log
import Core
import PrivacyConfig

/// Simple background task manager that provides a 15-second safety net when app goes to background
/// to allow ongoing operations to complete gracefully.
final class BackgroundTaskManager {
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTimer: Timer?
    private let featureFlagger: FeatureFlagger
    
    private static let backgroundTaskDuration: TimeInterval = 15.0
    private static let taskName = "App Background Safety Net"
    
    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }
    
    func startBackgroundTask() {
        guard featureFlagger.isFeatureOn(.genericBackgroundTask) else {
            return
        }
        
        endBackgroundTask()
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: Self.taskName) { [weak self] in
            self?.endBackgroundTask()
        }
        
        guard backgroundTaskID != .invalid else {
            return
        }
        
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: Self.backgroundTaskDuration, repeats: false) { [weak self] _ in
            self?.endBackgroundTask()
        }
    }
    
    func endBackgroundTask() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
