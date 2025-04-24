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
        
    private enum QueuedEvent {
        case mediaControl(pause: Bool)
        case serpNotification(enabled: Bool)
        case muteAudio(mute: Bool)
    }
    
    var isInitialized = false
    private var eventQueue: [QueuedEvent] = []
    var duckPlayer: DuckPlayerControlling
    private var cancellables = Set<AnyCancellable>()

    struct Constants {
        static let featureName = "duckPlayerNative"
        static let SERP = "SERP"
        static let YOUTUBE = "YOUTUBE"
        static let NOCOOKIE = "NOCOOKIE"
        static let UNKNOWN = "UNKNOWN"
        static let locale = "locale"
        static let pageType = "pageType"
        static let timestamp = "timestamp"
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
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie),
        .exact(hostname: DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW)
    ])
    public var featureName: String = Constants.featureName


    init(duckPlayer: DuckPlayerControlling) {
        self.duckPlayer = duckPlayer
        super.init()
        setupSubscriptions()
    }

    private func setupSubscriptions() {

        duckPlayer.mediaControlPublisher
            .sink { [weak self] pause in
                self?.handleMediaControl(pause: pause)
            }
            .store(in: &cancellables)

        duckPlayer.serpNotificationPublisher
            .sink { [weak self] enabled in
                self?.handleSerpNotification(enabled: enabled)
            }
            .store(in: &cancellables)

        duckPlayer.muteAudioPublisher
            .sink { [weak self] mute in
                self?.handleMuteAudio(mute: mute)
            }
            .store(in: &cancellables)

        duckPlayer.scriptInitializerPublisher
            .sink { [weak self] initialized in
                self?.isInitialized = initialized
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
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    

    private func handleMediaControl(pause: Bool) {
        guard let broker = broker, let webView = webView else { return }
        if !isInitialized {
            eventQueue.append(.mediaControl(pause: pause))
            return
        }
        print("DP: 🟣 Pushing onMediaControl event with pause: \(pause)")
        broker.push(method: "onMediaControl", params: ["pause": pause], for: self, into: webView)
    }

    private func handleSerpNotification(enabled: Bool) {
        guard let broker = broker, let webView = webView else { return }
        if !isInitialized {
            eventQueue.append(.serpNotification(enabled: enabled))
            return
        }
        print("DP: 🟣 Pushing handleSerpNotification with enabled: \(enabled)")
        broker.push(method: "onSerpNotify", params: ["enabled": enabled], for: self, into: webView)
    }

    private func handleMuteAudio(mute: Bool) {
        guard let broker = broker, let webView = webView else { return }
        if !isInitialized {
            eventQueue.append(.muteAudio(mute: mute))
            return
        }
        print("DP: 🟣 Pushing handleMuteAudio with mute: \(mute)")
        broker.push(method: "onMuteAudio", params: ["mute": mute], for: self, into: webView)
    }

    private func processEventQueue() {
        guard let broker = broker, let webView = webView else { return }
        
        for event in eventQueue {
            switch event {
            case .mediaControl(let pause):
                print("DP: 🟣 Processing queued onMediaControl event with pause: \(pause)")
                broker.push(method: "onMediaControl", params: ["pause": pause], for: self, into: webView)
            case .serpNotification(let enabled):
                print("DP: 🟣 Processing queued handleSerpNotification with enabled: \(enabled)")
                broker.push(method: "onSerpNotify", params: ["enabled": enabled], for: self, into: webView)
            case .muteAudio(let mute):
                print("DP: 🟣 Processing queued handleMuteAudio with mute: \(mute)")
                broker.push(method: "onMuteAudio", params: ["mute": mute], for: self, into: webView)
            }
        }
        eventQueue.removeAll()
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
        guard let webView = webView else { return nil }
        let locale = Locale.current.languageCode ?? "en"
        let pageType: String
        guard let host = webView.url?.host else { return nil }
        switch host {
        case DuckPlayerSettingsDefault.OriginDomains.duckduckgo:
            pageType = Constants.SERP
        // Only on watch pages
        case DuckPlayerSettingsDefault.OriginDomains.youtube, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeWWW, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeMobile:
            pageType = Constants.YOUTUBE
        case DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW:
            pageType = Constants.NOCOOKIE
        default:
            pageType = Constants.UNKNOWN
        }
        let result: [String: String] = [Constants.locale: locale, Constants.pageType: pageType]
        isInitialized = true

        // Process the event queue after the initial setup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.processEventQueue()
        }

        return result
    }

    @MainActor
    private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let timeString = dict[Constants.timestamp] as? String else {
            return nil
        }
        if let timeInterval = Double(timeString) {
            print("DP: 🟣 DuckPlayerNativeUserScript onCurrentTimeStamp Called: Time \(timeInterval)")
            duckPlayer.currentTimeStampPublisher.send(timeInterval)
        } else {
            print("DP: 🔴 DuckPlayerNativeUserScript onCurrentTimeStamp Called: Time \(timeString) is not a valid number")
        }
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: 🟣 DuckPlayerNativeUserScript onYoutubeError Called from UserScript")
        let result: [String: String] = [:]
        return result
    }

}
