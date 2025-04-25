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
        static let mute = "mute"
        static let pause = "pause"
        static let enabled = "enabled"
    }

    struct FEEvents {
        static let onMediaControl = "onMediaControl"
        static let onSerpNotify = "onSerpNotify"
        static let onMuteAudio = "onMuteAudio"
        static let onUrlChanged = "onUrlChanged"        
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
        print("DP: handleEvent: \(event)")
        if isFeatureReady {
            processEvent(event)
        } else {
            eventQueue.append(event)
        }   
    }

    private func processEvent(_ event: QueuedEvent) {
        switch event {
        case .mediaControl(let pause):
            pushToWebView(method: FEEvents.onMediaControl, params: [Constants.pause: String(pause)])
        case .serpNotification(let enabled):
            pushToWebView(method: FEEvents.onSerpNotify, params: [Constants.enabled: String(enabled)])
        case .muteAudio(let mute):
            pushToWebView(method: FEEvents.onMuteAudio, params: [Constants.mute: String(mute)])
        case .urlChanged(let pageType):
            pushToWebView(method: FEEvents.onUrlChanged, params: [Constants.pageType: pageType])
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

    internal func onUrlChanged() {
        print("DP: onUrlChanged")
        guard let webView = webView, 
              let url = webView.url,
              let host = url.host else { return }
        
        // Determine the page type based on the host and URL
        let pageType: String
        let shouldClearQueue: Bool
        
        switch host {
        case DuckPlayerSettingsDefault.OriginDomains.duckduckgo:
            pageType = Constants.SERP
            shouldClearQueue = true
        case DuckPlayerSettingsDefault.OriginDomains.youtube, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeWWW, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeMobile:
            if url.isYoutubeWatch {
                pageType = Constants.YOUTUBE
                shouldClearQueue = false
            } else {
                pageType = Constants.UNKNOWN
                shouldClearQueue = true
            }
        case DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie, 
             DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW:
            pageType = Constants.NOCOOKIE
            shouldClearQueue = true
        default:
            pageType = Constants.UNKNOWN
            shouldClearQueue = true
        }

        if shouldClearQueue {
            eventQueue.removeAll()
        }
        
        // If already ready, send directly; otherwise queue
        if isFeatureReady {
            print("DP: onUrlChanged: already ready")
            pushToWebView(method: FEEvents.onUrlChanged, params: [Constants.pageType: pageType])
        } else {
            print("DP: onUrlChanged: not ready")
            isFeatureReady = false
            handleEvent(.urlChanged(pageType: pageType))
        }
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: initialSetup")
        let result: [String: String] = [Constants.locale: Locale.current.languageCode ?? "en"]
        return result
    }

    @MainActor
    private func onCurrentTimeStamp(params: Any, original: WKScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let timeString = dict[Constants.timestamp] as? String,
              let timeInterval = Double(timeString) else {
            return [:] as [String: String]
        }
        duckPlayer.currentTimeStampPublisher.send(timeInterval)
        return [:] as [String: String]
    }

    @MainActor
    private func onYoutubeError(params: Any, original: WKScriptMessage) -> Encodable? {
        return [:] as [String: String]
    }

    @MainActor
    internal func onDuckPlayerReady(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: onDuckPlayerReady")
        isFeatureReady = true
        // Process all queued events
        while !eventQueue.isEmpty {
            let event = eventQueue.removeFirst()
            processEvent(event)
        }
        return nil
    }

}
