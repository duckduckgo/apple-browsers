//
//  LaunchProfileStartup.swift
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

#if DEBUG || ALPHA

import AIChat
import Core
import Foundation
import LaunchProfile
import os.log
import UIKit

/// Applies `-launchProfile` on the way into `Launching`, before any dependency is built,
/// so every service reads the profile's state on its first read.
@MainActor
enum LaunchProfileStartup {

    static func applyIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let outcome: LaunchProfileOutcome
        do {
            guard let profile = try LaunchProfile.load(arguments: arguments) else { return }
            outcome = liveSettings().apply(profile)
        } catch {
            outcome = .rejected([LaunchProfileProblem(key: nil, message: "\(error)")])
        }
        report(outcome)
    }

    private static func liveSettings() -> LaunchSettings {
        IOSLaunchSettings.make(.init(
            internalUserStore: InternalUserStore(),
            flagOverridesNeedInternalUser: !LaunchOptionsHandler().isUITesting,
            setLaunchArgument: setForThisLaunch(_:forKey:),
            tabsPersistence: { try TabsModelPersistence() },
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            appSettings: AppUserDefaults(),
            appDefaults: .app,
            appConfigurationDefaults: UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults(),
            aiChatDebugSettings: AIChatDebugSettings(),
            statistics: StatisticsUserDefaults()
        ))
    }

    /// Reads exactly like a launch argument: the argument domain is never saved, so the value lasts one launch.
    private static func setForThisLaunch(_ value: String, forKey key: String) {
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[key] = value
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// Printed to stderr too, so `xcrun simctl launch --console-pty` shows it.
    private static func report(_ outcome: LaunchProfileOutcome) {
        let line = outcome.logLine
        if outcome.isSuccess {
            Logger.launchProfile.log("\(line, privacy: .public)")
        } else {
            Logger.launchProfile.error("\(line, privacy: .public)")
        }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

private extension Logger {
    static let launchProfile = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "LaunchProfile")
}

#endif
