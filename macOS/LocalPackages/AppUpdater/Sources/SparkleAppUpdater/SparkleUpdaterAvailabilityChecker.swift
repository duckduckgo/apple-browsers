//
//  SparkleUpdaterAvailabilityChecker.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import AppUpdaterShared
import Foundation
import Sparkle

public final class SparkleUpdaterAvailabilityChecker: UpdaterAvailabilityChecking {
    public var updater: UpdaterAvailabilityChecking?

    /// When the update is not available (equal to nil) we will return true so the Updater can
    /// check for the last try instead.
    public var canCheckForUpdates: Bool {
        return updater?.canCheckForUpdates ?? true
    }

    public init(updater: UpdaterAvailabilityChecking? = nil) {
        self.updater = updater
    }
}
