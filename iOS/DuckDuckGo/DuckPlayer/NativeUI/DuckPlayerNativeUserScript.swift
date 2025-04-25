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
        case urlChanged(pageType: String)
    }
    
    var isFeatureReady = false
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
        static let onDuckPlayerReady = "onDuckPlayerReady"
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

        duckPlayer.urlChangedPublisher
            .sink { [weak self] initialized in
                self?.onUrlChanged()
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
        case Handlers.onDuckPlayerReady:
            return onDuckPlayerReady
        default:
            return nil
        }
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    

    private func pushToWebView(method: String, params: [String: String]) {
        guard let broker = broker, let webView = webView else { return }
        broker.push(method: method, params: params, for: self, into: webView)
    }

    private func handleEvent(_ event: QueuedEvent) {
        if isFeatureReady {
            processEvent(event)
        } else {
            eventQueue.append(event)
        }
    }

    private func processEvent(_ event: QueuedEvent) {
        switch event {
        case .mediaControl(let pause):
            pushMediaControl(pause: pause)
        case .serpNotification(let enabled):
            pushSerpNotification(enabled: enabled)
        case .muteAudio(let mute):
            pushMuteAudio(mute: mute)
        case .urlChanged(let pageType):
            pushUrlChanged(pageType: pageType)
        }
    }

    private func handleMediaControl(pause: Bool) {
        handleEvent(.mediaControl(pause: pause))
    }

    private func handleSerpNotification(enabled: Bool) {
        handleEvent(.serpNotification(enabled: enabled))
    }

    private func handleMuteAudio(mute: Bool) {
        handleEvent(.muteAudio(mute: mute))
    }

    private func onUrlChanged() {
        guard let webView = webView else { return }         
        let pageType: String
        guard let host = webView.url?.host else { return }
        guard let url = webView.url else { return }
        switch host {
        case DuckPlayerSettingsDefault.OriginDomains.duckduckgo:
            pageType = Constants.SERP
        case DuckPlayerSettingsDefault.OriginDomains.youtube, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeWWW, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeMobile:
            if url.isYoutubeWatch {
                pageType = Constants.YOUTUBE
            } else {
                pageType = Constants.UNKNOWN
            }
        case DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW:
            pageType = Constants.NOCOOKIE
        default:
            pageType = Constants.UNKNOWN
        }

        isFeatureReady = false
        eventQueue.removeAll()
        handleEvent(.urlChanged(pageType: pageType))
    }

    private func pushMediaControl(pause: Bool) {
        pushToWebView(method: "onMediaControl", params: ["pause": String(pause)])
    }

    private func pushSerpNotification(enabled: Bool) {
        pushToWebView(method: "onSerpNotify", params: ["enabled": String(enabled)])
    }

    private func pushMuteAudio(mute: Bool) {
        pushToWebView(method: "onMuteAudio", params: ["mute": String(mute)])
    }

    private func pushUrlChanged(pageType: String) {
        pushToWebView(method: "onUrlChanged", params: [Constants.pageType: pageType])
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {            
        let locale = Locale.current.languageCode ?? "en"
        let result: [String: String] = [Constants.locale: locale]
        return result
    }

    @MainActor
    private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let timeString = dict[Constants.timestamp] as? String else {
            return nil
        }
        if let timeInterval = Double(timeString) {
            duckPlayer.currentTimeStampPublisher.send(timeInterval)
        } else {
        }
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
        let result: [String: String] = [:]
        return result
    }

    @MainActor
    private func onDuckPlayerReady(params: Any, original: WKScriptMessage) -> Encodable? {        
        isFeatureReady = true
        while !eventQueue.isEmpty {
            if let event = eventQueue.first {
                processEvent(event)
                eventQueue.removeFirst()
            }
        }
        return nil
    }

}
