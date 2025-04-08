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
    
    @Published var currentTimeStamp: Int = 0

    struct Constants {
        static let featureName = "duckPlayerNative"
    }

    struct Handlers {
        static let initialSetup = "initialSetup"
        static let onCurrentTimeStamp = "onGetCurrentTimestamp"
        static let onYoutubeError = "onYoutubeError"
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

    override init() {
        super.init()
        print("DuckPlayerNativeUserScript init")
    }

    // MARK: - Subfeature

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    // MARK: - MessageNames

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case Handlers.onCurrentTimeStamp:
            return onCurrentTimeStamp
        case Handlers.onYoutubeError:
            return onYoutubeError
        case Handlers.initialSetup:
            return initialSetup
        default:
            assertionFailure("Failed to parse script message: \(methodName)")
            return nil
        }
    }

    public func muteAudio(mute: Bool) {
        let params = ["mute": mute]
        if let webView {
            broker?.push(method: "onMuteAudio", params: params, for: self, into: webView)
        }
    }

    public func getCurrentTimeStamp(mute: Bool) {
        let params: [String: String] = [:]
        if let webView {
            broker?.push(method: "onGetCurrentTimestamp", params: params, for: self, into: webView)
        }
    }

    public func serpNotification(enabled: Bool) {
        let params = ["enabled": enabled]
        if let webView {
            broker?.push(method: "onSerpNotify", params: params, for: self, into: webView)
        }
    }

   public func mediaControl(pause: Bool) {
        let params = ["pause": pause]
        if let webView {
            broker?.push(method: "onMediaControl", params: params, for: self, into: webView)
        }
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DuckPlayerNativeUserScript initialSetup")
        return nil
    }

    @MainActor
    private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
          guard let dict = params as? [String: Any],
                let time = dict["timestamp"] as? String else {
            assertionFailure("Could not parse WKMessage to obtain video details")
            return nil
        }
        currentTimeStamp = Int(time) ?? 0
        print("DuckPlayerNativeUserScript onCurrentTimeStamp: \(currentTimeStamp)")
        return nil
    }

    @MainActor
    private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DuckPlayerNativeUserScript onYoutubeError")
        return nil
    }

}
