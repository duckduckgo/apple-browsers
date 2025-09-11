//
//  SurrogatesUserScript.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Common
import ContentBlocking
import TrackerRadarKit
import UserScript
@preconcurrency import WebKit

public protocol SurrogatesUserScriptDelegate: NSObjectProtocol {

    func surrogatesUserScriptShouldProcessTrackers(_ script: SurrogatesUserScript) -> Bool
    func surrogatesUserScriptShouldProcessCTLTrackers(_ script: SurrogatesUserScript) -> Bool
    func surrogatesUserScript(_ script: SurrogatesUserScript,
                              detectedTracker tracker: DetectedRequest,
                              withSurrogate host: String)

}

public protocol SurrogatesUserScriptConfig: UserScriptSourceProviding {

    var privacyConfig: PrivacyConfiguration { get }
    var surrogates: String { get }
    var trackerData: TrackerData? { get }
    var encodedSurrogateTrackerData: String? { get }
    var tld: TLD { get }

}

public class DefaultSurrogatesUserScriptConfig: SurrogatesUserScriptConfig {

    public let privacyConfig: PrivacyConfiguration
    public let surrogates: String
    public let trackerData: TrackerData?
    public let encodedSurrogateTrackerData: String?
    public let tld: TLD

    public let source: String

    public init(privacyConfig: PrivacyConfiguration,
                surrogates: String,
                trackerData: TrackerData?,
                encodedSurrogateTrackerData: String?,
                trackerDataManager: TrackerDataManager,
                tld: TLD,
                isDebugBuild: Bool) throws {

        if trackerData == nil {
            // Fallback to embedded
            self.trackerData = trackerDataManager.trackerData

            let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: trackerDataManager.trackerData)
            let encodedData = try? JSONEncoder().encode(surrogateTDS)
            let encodedTrackerData = String(data: encodedData!, encoding: .utf8)!
            self.encodedSurrogateTrackerData = encodedTrackerData
        } else {
            self.trackerData = trackerData
            self.encodedSurrogateTrackerData = encodedSurrogateTrackerData
        }

        self.privacyConfig = privacyConfig
        self.surrogates = surrogates
        self.tld = tld

        source = try SurrogatesUserScript.generateSource(privacyConfiguration: self.privacyConfig,
                                                         surrogates: self.surrogates,
                                                         encodedSurrogateTrackerData: self.encodedSurrogateTrackerData,
                                                         isDebugBuild: isDebugBuild)
    }
}

open class SurrogatesUserScript: NSObject, UserScript, WKScriptMessageHandlerWithReply {
    struct TrackerDetectedKey {
        static let protectionId = "protectionId"
        static let blocked = "blocked"
        static let networkName = "networkName"
        static let url = "url"
        static let isSurrogate = "isSurrogate"
        static let pageUrl = "pageUrl"
    }

    private let configuration: SurrogatesUserScriptConfig

    public init(configuration: SurrogatesUserScriptConfig) {
        self.configuration = configuration

        super.init()
    }

    open var source: String {
        return configuration.source
    }

    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart

    public var forMainFrameOnly: Bool = false

    public var requiresRunInPageContentWorld: Bool = true

    public var messageNames: [String] = [
        "trackerDetectedMessage",
        "isCTLEnabled"
    ]

    public weak var delegate: SurrogatesUserScriptDelegate?

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {

        guard let delegate = delegate else { return }

        if message.name == "isCTLEnabled" {
            let ctlEnabled = delegate.surrogatesUserScriptShouldProcessCTLTrackers(self)
            replyHandler(ctlEnabled, nil)
            return
        } else if message.name == "trackerDetectedMessage"	{
            guard delegate.surrogatesUserScriptShouldProcessTrackers(self) else { return }

            guard let dict = message.body as? [String: Any] else { return }
            guard let blocked = dict[TrackerDetectedKey.blocked] as? Bool else { return }
            guard let urlString = dict[TrackerDetectedKey.url] as? String else { return }
            guard let pageUrlStr = dict[TrackerDetectedKey.pageUrl] as? String else { return }

            let tracker = trackerFromUrl(urlString.trimmingWhitespace(), pageUrlString: pageUrlStr, blocked)

            if let isSurrogate = dict[TrackerDetectedKey.isSurrogate] as? Bool, isSurrogate, let host = URL(string: urlString)?.host {
                delegate.surrogatesUserScript(self, detectedTracker: tracker, withSurrogate: host)
            }
            replyHandler(nil, nil)
            return
        }

        replyHandler(nil, "Unknown message")
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        assertionFailure("Should never be here!")
    }

    private func trackerFromUrl(_ urlString: String, pageUrlString: String, _ blocked: Bool) -> DetectedRequest {
        let currentTrackerData = configuration.trackerData
        let knownTracker = currentTrackerData?.findTracker(forUrl: urlString)
        let entity = currentTrackerData?.findEntity(byName: knownTracker?.owner?.name ?? "")

        let eTLDp1 = configuration.tld.eTLDplus1(forStringURL: urlString)
        return DetectedRequest(url: urlString,
                               eTLDplus1: eTLDp1,
                               knownTracker: knownTracker,
                               entity: entity,
                               state: .blocked,
                               pageUrl: pageUrlString)
    }

    private static func createSurrogateFunctions(_ surrogates: String) -> String {
        let commentlessSurrogates = surrogates.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).filter {
            return !$0.starts(with: "#")
        }.joined(separator: "\n")
        let surrogateScripts = commentlessSurrogates.components(separatedBy: "\n\n")

        // Construct a JavaScript object for function lookup
        let surrogatesOut = surrogateScripts.map { (surrogate) -> String in
            var codeLines = surrogate.split(separator: "\n")
            if codeLines.isEmpty {
                return ""
            }
            let instructionsRow = codeLines.removeFirst()
            guard let path = instructionsRow.split(separator: " ").first,
                  let pattern = path.split(separator: "/").last else {
                return ""
            }
            let stringifiedFunction = codeLines.joined(separator: "\n")
            return "surrogates['\(pattern)'] = function () {\(stringifiedFunction)}"
        }
        return surrogatesOut.joined(separator: "\n")
    }

    public static func generateSource(privacyConfiguration: PrivacyConfiguration,
                                      surrogates: String,
                                      encodedSurrogateTrackerData: String?,
                                      isDebugBuild: Bool) throws -> String {
        let remoteUnprotectedDomains = (privacyConfiguration.tempUnprotectedDomains.joined(separator: "\n"))
            + "\n"
            + (privacyConfiguration.exceptionsList(forFeature: .contentBlocking).joined(separator: "\n"))

        // Encode whatever the tracker data manager is using to ensure it's in sync and because we know it will work
        let trackerData: String
        if let data = encodedSurrogateTrackerData {
            trackerData = data
        } else {
            let encodedData = try? JSONEncoder().encode(TrackerData(trackers: [:], entities: [:], domains: [:], cnames: [:]))
            trackerData = String(data: encodedData!, encoding: .utf8)!
        }

        return try SurrogatesUserScript.loadJS("surrogates", from: Bundle.module, withReplacements: [
            "$IS_DEBUG$": isDebugBuild ? "true" : "false",
            "$TEMP_UNPROTECTED_DOMAINS$": remoteUnprotectedDomains,
            "$USER_UNPROTECTED_DOMAINS$": privacyConfiguration.userUnprotectedDomains.joined(separator: "\n"),
            "$TRACKER_ALLOWLIST_ENTRIES$": TrackerAllowlistInjection.prepareForInjection(allowlist: privacyConfiguration.trackerAllowlist.entries),
            "$TRACKER_DATA$": trackerData,
            "$SURROGATES$": createSurrogateFunctions(surrogates),
            "$BLOCKING_ENABLED$": privacyConfiguration.isEnabled(featureKey: .contentBlocking) ? "true" : "false"
        ])
    }
}
