//
//  ContentBlockerRulesSource.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit

/**
 Represents all sources used to build Content Blocking Rules.
 */
public protocol ContentBlockerRulesListsSource {

    var contentBlockerRulesLists: [ContentBlockerRulesList] { get }
}

/**
 Represents sources used to prepare exceptions to content blocking Rules.
 */
public protocol ContentBlockerRulesExceptionsSource {

    var tempListId: String { get }
    var tempList: [String] { get }
    var allowListId: String { get }
    var allowList: [TrackerException] { get }
    var unprotectedSites: [String] { get }
}

public class ContentBlockerRulesList {

    private var getTrackerData: (() -> TrackerDataManager.DataSet?)!
    public lazy var trackerData: TrackerDataManager.DataSet? = {
        let getTrackerData = self.getTrackerData
        self.getTrackerData = nil
        return getTrackerData!()
    }()
    private var getFallbackTrackerData: (() -> TrackerDataManager.DataSet)!
    public lazy var fallbackTrackerData: TrackerDataManager.DataSet = {
        let getFallbackTrackerData = self.getFallbackTrackerData
        self.getFallbackTrackerData = nil
        return getFallbackTrackerData!()
    }()

    public let name: String

    public init(name: String,
                trackerData: @escaping @autoclosure () -> TrackerDataManager.DataSet?,
                fallbackTrackerData: @escaping @autoclosure () -> TrackerDataManager.DataSet) {
        self.name = name
        self.getTrackerData = trackerData
        self.getFallbackTrackerData = fallbackTrackerData
    }
}

open class DefaultContentBlockerRulesListsSource: ContentBlockerRulesListsSource {

    public struct Constants {
        public static let trackerDataSetRulesListName = "TrackerDataSet"
        public static let clickToLoadRulesListName = "ClickToLoad"
    }

    private let trackerDataManager: TrackerDataManager

    public init(trackerDataManager: TrackerDataManager) {
        self.trackerDataManager = trackerDataManager
    }

    open var contentBlockerRulesLists: [ContentBlockerRulesList] {
        return [ContentBlockerRulesList(name: Constants.trackerDataSetRulesListName,
                                        trackerData: self.trackerDataManager.fetchedData,
                                        fallbackTrackerData: self.trackerDataManager.embeddedData)]
    }
}

public class DefaultContentBlockerRulesExceptionsSource: ContentBlockerRulesExceptionsSource {

    let privacyConfigManager: PrivacyConfigurationManaging

    public init(privacyConfigManager: PrivacyConfigurationManaging) {
        self.privacyConfigManager = privacyConfigManager
    }

    public var tempListId: String {
        return ContentBlockerRulesIdentifier.hash(domains: tempList)
    }

    public var tempList: [String] {
        let config = privacyConfigManager.privacyConfig
        var tempUnprotected = config.tempUnprotectedDomains.filter { !$0.trimmingWhitespace().isEmpty }
        tempUnprotected.append(contentsOf: config.exceptionsList(forFeature: .contentBlocking))
        return tempUnprotected
    }

    public var allowListId: String {
        return privacyConfigManager.privacyConfig.trackerAllowlist.hash ?? privacyConfigManager.privacyConfig.identifier
    }

    public var allowList: [TrackerException] {
        return Self.transform(allowList: privacyConfigManager.privacyConfig.trackerAllowlist.entries)
    }

    public var unprotectedSites: [String] {
        return privacyConfigManager.privacyConfig.userUnprotectedDomains
    }

    public class func transform(allowList: PrivacyConfigurationData.TrackerAllowlistData) -> [TrackerException] {

        let trackerRules = allowList.values.reduce(into: []) { partialResult, next in
            partialResult.append(contentsOf: next)
        }

        return trackerRules.map { entry in
            if entry.domains.contains("<all>") {
                return TrackerException(rule: entry.rule, matching: .all)
            } else {
                return TrackerException(rule: entry.rule, matching: .domains(entry.domains.normalizedDomainsForContentBlocking()))
            }
        }
    }

}
