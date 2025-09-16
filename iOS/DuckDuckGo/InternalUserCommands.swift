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
import BrowserServicesKit

/// Used to specify custom commands executed through Favorite shortcuts from Home Screen or overlay

protocol URLBasedDebugCommands {
    func handle(url: URL) -> Bool
}

class InternalUserCommands: URLBasedDebugCommands {

    enum Constants {
        static let scheme = "ddg-internal"
    }

    enum Command: String {
        case reloadConfig
    }

    init(internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: InternalUserStore()),
         presenter: ActionMessagePresenting.Type = ActionMessageView.self,
         configFetching: AppConfigurationFetching = AppConfigurationFetch()) {
        self.internalUserDecider = internalUserDecider
        self.presenter = presenter
        self.configFetching = configFetching
    }

    let internalUserDecider: InternalUserDecider
    let presenter: ActionMessagePresenting.Type
    let configFetching: AppConfigurationFetching

    private func present(message: String) {
        DispatchQueue.main.async {
            self.presenter.present(message: message,
                                   actionTitle: nil,
                                   presentationLocation: .withBottomBar(andAddressBarBottom: false),
                                   duration: 3.0,
                                   onAction: {}, onDidDismiss: {})
        }
    }

    public func handle(url: URL) -> Bool {
        guard internalUserDecider.isInternalUser,
              url.scheme == Constants.scheme else { return false }

        guard let command = Command(rawValue: url.host ?? "") else {
            self.present(message: "Unknown command")
            return true
        }

        switch command {
        case .reloadConfig:
            configFetching.start(isBackgroundFetch: false,
                                 isDebug: true,
                                 forceRefresh: true) { result in
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
