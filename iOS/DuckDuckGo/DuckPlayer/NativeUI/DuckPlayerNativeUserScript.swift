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
        static let onCurrentTimeStamp = "onCurrentTimestamp"
        static let onYoutubeError = "onYoutubeError"
    }

    weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView?
    let duckPlayer: DuckPlayerControlling

    let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.duckduckgo),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtube),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeMobile),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeWWW),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie)
    ])
    public var featureName: String = Constants.featureName

    private var cancellables = Set<AnyCancellable>()

    init(duckPlayer: DuckPlayerControlling) {
        self.duckPlayer = duckPlayer
        super.init()
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        
        duckPlayer.mediaControlPublisher.sink { [weak self] pause in
            print("DP: Received mediaControl update: \(pause)")
            guard let self = self, let broker = self.broker, let webView = self.webView else {
                print("DP: Error: Broker or webView not available for mediaControl update.")
                return
            }
            print("DP: Sending Broker message onMediaControl: \(pause)")
            broker.push(method: "onMediaControl", params: ["pause": pause], for: self, into: webView)
        }
        .store(in: &cancellables)

        duckPlayer.serpNotificationPublisher.sink { [weak self] enabled in
            print("DP: Received serpNotification update: \(enabled)")
            guard let self = self, let broker = self.broker, let webView = self.webView else {
                print("DP: Error: Broker or webView not available for serpNotification update.")
                return
            }
            print("DP: Sending Broker message onSerpNotification: \(enabled)")
            broker.push(method: "onSerpNotification", params: ["enabled": enabled], for: self, into: webView)
        }
        .store(in: &cancellables)

        duckPlayer.muteAudioPublisher.sink { [weak self] mute in
            print("DP: Received muteAudio update: \(mute)")
            guard let self = self, let broker = self.broker, let webView = self.webView else {
                print("DP: Error: Broker or webView not available for muteAudio update.")
                return
            }
            print("DP: Sending Broker message onMuteAudio: \(mute)")
            broker.push(method: "onMuteAudio", params: ["mute": mute], for: self, into: webView)
        }
        .store(in: &cancellables)
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
            return nil
        }
    }
    

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: DuckPlayerNativeUserScript initialSetup Called from UserScript")
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
        //print("DP: DuckPlayerNativeUserScript onCurrentTimeStamp Called from UserScript")
        guard let dict = params as? [String: Any],
              let time = dict["timestamp"] as? String else {
            return nil
        }        
        currentTimeStamp = Int(time) ?? 0
        duckPlayer.currentTimeStampPublisher.send(TimeInterval(currentTimeStamp))
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: DuckPlayerNativeUserScript onYoutubeError Called from UserScript")
        let result: [String: String] = [:]
        return result
    }

}
