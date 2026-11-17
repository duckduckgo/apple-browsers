//
//  AppStoreBuildSimulation.swift
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

import AppKitExtensions
import Foundation

/// Debug setting that makes a direct-download build handle web extensions as the App Store build does.
protocol AppStoreBuildSimulationProtocol: AnyObject {
    var isEnabled: Bool { get set }
}

final class AppStoreBuildSimulation: AppStoreBuildSimulationProtocol {
    private enum Key {
        static let isEnabled = "web-extensions.debug.simulate-app-store-build"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Key.isEnabled) }
        set { userDefaults.set(newValue, forKey: Key.isEnabled) }
    }
}

/// The build type web extensions use: the App Store build, or a direct-download build simulating it.
struct WebExtensionsBuildType: ApplicationBuildType {
    let isAppStoreBuild: Bool
    let isDebugBuild: Bool
    let isReviewBuild: Bool
    let isAlphaBuild: Bool

    var isSparkleBuild: Bool { !isAppStoreBuild }

    init(base: ApplicationBuildType, simulation: AppStoreBuildSimulationProtocol) {
        isAppStoreBuild = base.isAppStoreBuild || simulation.isEnabled
        isDebugBuild = base.isDebugBuild
        isReviewBuild = base.isReviewBuild
        isAlphaBuild = base.isAlphaBuild
    }
}
