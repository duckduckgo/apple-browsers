
//  DuckPlayerNativeUserScript.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import WebKit
import Common
import UserScript
import Combine
import Core
import BrowserServicesKit
import DuckPlayer

final class DuckPlayerNativeUserScript: NSObject, Subfeature {
        
    struct Constants {
        static let featureName = "duckPlayerNative"
    }

    struct Handlers {
        static let setUserValues = "initialSetup"
        static let getUserValues = "onGetCurrentTimestamp"
        static let openDuckPlayer = "onMediaControl"
        static let sendDuckPlayerPixel = "onMuteAudio"
        static let initialSetup = "onSerpNotify"
        static let openInfo = "onYoutubeError"
    }

    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?

    let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.duckduckgo),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtube),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeMobile),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeWWW)
    ])
    public var featureName: String = Constants.featureName

    // MARK: - Subfeature

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    // MARK: - MessageNames

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case Handlers.initialSetup:
            return
        case Handlers.getCurrentTimestamp:
            return
        case Handlers.onMediaControl:
            return
        case Handlers.onMuteAudio:
            return
        case Handlers.onSerpNotify:
            return
        case Handlers.onYoutubeError:
            return
        default:
            assertionFailure("Failed to parse script message: \(methodName)")
            return nil
        }
    }

    
}}
