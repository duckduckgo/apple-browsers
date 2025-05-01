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
/**
 DuckPlayerNativeUserScript
 
 This class manages the communication between the native Duck Player UI and the web content via user scripts. It is responsible for queuing and dispatching events to the webview in a controlled manner, ensuring that events are only sent when the web content is ready to handle them.
 
 ## Dual-Queue Event Handling
 
 The event flow is split into two distinct phases, each with its own queue:
 
 - **URL Change Events**: These are queued and only dispatched when the web content signals that the DuckPlayer feature is ready (via the `onDuckPlayerFeatureReady` message). Only the latest URL change event is kept in the queue, ensuring that the webview always receives the most up-to-date navigation state.
 
 - **Other Events**: All other events (such as media control, mute, and notifications) are queued separately and are only dispatched when the web content signals that all scripts are ready (via the `onDuckPlayerScriptsReady` message). This ensures that no event is lost or sent prematurely during page reloads or script initialization.
 
 After every page reload, the URL change event is queued and sent after the feature is ready, while all other events are queued and sent after the scripts are ready. This design guarantees robust and predictable communication between the native and web layers, even in the presence of navigation or reloads.
 
 - Author: DuckDuckGo
 - Since: 2024
 */

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
    
    private var otherEventsQueue: [QueuedEvent] = []
    private var areScriptsReady = false
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
        static let onDuckPlayerFeatureReady = "onDuckPlayerFeatureReady"
        static let onDuckPlayerScriptsReady = "onDuckPlayerScriptsReady"
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
        case Handlers.onDuckPlayerScriptsReady:
            return onDuckPlayerScriptsReady
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
        switch event {
        case .urlChanged:
            processEvent(event) // No need to queue url changes anymore
        default:
            if areScriptsReady {
                processEvent(event)
            } else {
                otherEventsQueue.append(event)
            }
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

    internal func getPageType() -> String {
        guard let webView = webView,
              let url = webView.url,
              let host = url.host else { return Constants.UNKNOWN }
        
        switch host {
        case DuckPlayerSettingsDefault.OriginDomains.duckduckgo:
            return Constants.SERP
        case DuckPlayerSettingsDefault.OriginDomains.youtube,
             DuckPlayerSettingsDefault.OriginDomains.youtubeWWW,
             DuckPlayerSettingsDefault.OriginDomains.youtubeMobile:
            if url.isYoutubeWatch {
                return Constants.YOUTUBE
            } else {
                return Constants.UNKNOWN
            }
        case DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookie,
             DuckPlayerSettingsDefault.OriginDomains.youtubeNoCookieWWW:
            return Constants.NOCOOKIE
        default:
            return Constants.UNKNOWN
        }
}
    
    internal func onUrlChanged() {
        print("DP: onUrlChanged")
        areScriptsReady = false
        
        // Determine the page type based on the host and URL
        let pageType = getPageType()
        let shouldClearEvents = pageType != Constants.YOUTUBE

        if shouldClearEvents {
            otherEventsQueue.removeAll()
        }
        
        // Always store the latest URL change event
        handleEvent(.urlChanged(pageType: pageType))
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: initialSetup")
        
        let pageType = getPageType()
        let result: [String: String] = [
            Constants.locale: Locale.current.languageCode ?? "en",
            Constants.pageType: pageType
        ]
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

    /**
     Handles the message indicating the DuckPlayer scripts are ready. This will send all queued events to the webview.
     - Parameters:
        - params: The parameters from the message.
        - original: The original WKScriptMessage.
     - Returns: nil
     */
    @MainActor
    internal func onDuckPlayerScriptsReady(params: Any, original: WKScriptMessage) -> Encodable? {
        print("DP: onDuckPlayerScriptsReady")
        areScriptsReady = true
        // Send all queued events
        while !otherEventsQueue.isEmpty {
            let event = otherEventsQueue.removeFirst()
            processEvent(event)
        }
        return nil
    }

}
