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
        
    var duckPlayer: DuckPlayerControlling
    private var cancellables = Set<AnyCancellable>()

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
    

    let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.duckduckgo),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtube),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeMobile),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeWWW),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie)
    ])
    public var featureName: String = Constants.featureName
    

    init(duckPlayer: DuckPlayerControlling) {
        self.duckPlayer = duckPlayer
        super.init()
        // Ensure duckPlayer is treated as an object for ObjectIdentifier
        if let object = duckPlayer as? AnyObject {
             print("DP: 🔴 DUCKPLAYER_NATIVE_USERSCRIPT: Initializing with DuckPlayer instance ID: \(ObjectIdentifier(object))")
        } else {
             print("DP: 🔴 DUCKPLAYER_NATIVE_USERSCRIPT: Initializing with DuckPlayer, but it's not an AnyObject.")
        }
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        print("🟢 DUCKPLAYER_NATIVE_USERSCRIPT: Setting up subscriptions")
        
        duckPlayer.mediaControlPublisher
            .sink { [weak self] pause in
                print("🟢 DUCKPLAYER_NATIVE_USERSCRIPT: Received mediaControlPublisher event: \(pause)")
                self?.handleMediaControl(pause: pause)
            }
            .store(in: &cancellables)

        duckPlayer.serpNotificationPublisher
            .sink { [weak self] enabled in
                 print("🟢 DUCKPLAYER_NATIVE_USERSCRIPT: Received serpNotificationPublisher event: \(enabled)")
                self?.handleSerpNotification(enabled: enabled)
            }
            .store(in: &cancellables)

        duckPlayer.muteAudioPublisher
            .sink { [weak self] mute in
                 print("🟢 DUCKPLAYER_NATIVE_USERSCRIPT: Received muteAudioPublisher event: \(mute)")
                self?.handleMuteAudio(mute: mute)
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

    deinit {
        print("DP: 🟢 DuckPlayerNativeUserScript deinit called")
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    

    private func handleMediaControl(pause: Bool) {
        guard let broker = broker, let webView = webView else { return }
        print("DP: 🟢 handleMediaControl called with pause: \(pause)")
        broker.push(method: "onMediaControl", params: ["pause": pause], for: self, into: webView)
    }

    private func handleSerpNotification(enabled: Bool) {
        guard let broker = broker, let webView = webView else { return }
        print("DP: 🟢 handleSerpNotification called with enabled: \(enabled)")
        broker.push(method: "onSerpNotification", params: ["enabled": enabled], for: self, into: webView)
    }

    private func handleMuteAudio(mute: Bool) {
        guard let broker = broker, let webView = webView else { return }
        print("DP: 🟢 handleMuteAudio called with mute: \(mute)")
        broker.push(method: "onMuteAudio", params: ["mute": mute], for: self, into: webView)
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: 🟢 DuckPlayerNativeUserScript initialSetup Called from UserScript")
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
        //print("DP: 🟢 DuckPlayerNativeUserScript onCurrentTimeStamp Called from UserScript")
        guard let dict = params as? [String: Any],
              let time = dict["timestamp"] as? String else {
            return nil
        }
        duckPlayer.currentTimeStampPublisher.send(TimeInterval(Int(time) ?? 0))
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: 🟢 DuckPlayerNativeUserScript onYoutubeError Called from UserScript")
        let result: [String: String] = [:]
        return result
    }

}
