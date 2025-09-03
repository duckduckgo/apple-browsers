//
//  InternalUserCommands.swift
//  DuckDuckGo
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

import Core
import UIKit
import Foundation

/// Used to specify custom commands executed through Favorite shortcuts from Home Screen or overlay
class InternalUserCommands {

    enum Constants {
        static let scheme = "ddg-internal"
    }

    enum Command: String {
        case reloadConfig
    }

    private func present(message: String) {
        DispatchQueue.main.async {
            ActionMessageView.present(message: message)
        }
    }

    public func handle(url: URL) -> Bool {
        guard InternalUserStore().isInternalUser || isDebugBuild,
              url.scheme == Constants.scheme else { return false }

        guard let command = Command(rawValue: url.host ?? "") else {
            self.present(message: "Unknown command")
            return true
        }

        switch command {
        case .reloadConfig:
            AppConfigurationFetch().start(isDebug: true) { result in
                switch result {
                case .assetsUpdated(let protectionsUpdated):
                    if protectionsUpdated {
                        self.present(message: "Data updated, reloading rules")
                        ContentBlocking.shared.contentBlockingManager.scheduleCompilation()
                    } else {
                        self.present(message: "Data fetched, no changes to protections")
                    }
                case .noData:
                    self.present(message: "No new data")
                }
            }
        }

        return true
    }


}
