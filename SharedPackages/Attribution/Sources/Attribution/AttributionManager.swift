//
//  AttributionManager.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
//

import Foundation
import PixelKit
import Combine
import BrowserServicesKit
import os.log

/// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053?focus=true
public final class AttributionManager {

    private let pixelKit: PixelKit
    private var dataStorage: AttributionDataStoring
    private let originProvider: (any AttributionOriginProvider)?
    private let featureFlagger: FeatureFlagger
    var cancellables = Set<AnyCancellable>()

    public init(pixelKit: PixelKit, dataStoring: AttributionDataStoring, featureFlagger: FeatureFlagger, originProvider: (any AttributionOriginProvider)?) {
        self.pixelKit = pixelKit
        self.dataStorage = dataStoring
        self.originProvider = originProvider
        self.featureFlagger = featureFlagger

        if isEnabled {
            registerNotifications()
        }
    }

    // MARK: -

    var isEnabled: Bool {
        featureFlagger.isFeatureOn(for: AttributionFeatureFlags.attributionEnabled)
    }

    lazy var originOrInstall: (origin: String?, installDate: String?) = {
        if let origin = originProvider?.origin {
            return (origin, nil)
        } else {
            guard var installDate = dataStorage.appStarts?.timestamps.first else {
                assertionFailure("Missing install date")
                return (nil, nil)
            }
            return (nil, installDate.ISO8601Format())
        }
    }()

    var isDefaultBrowser: Bool {
        return true // TODO: implement
    }

    var isLessThanSixMonths: Bool {
        return true
    }

    // MARK: - Triggers

    func appDidStart() {
        guard isEnabled else { return }

        guard isLessThanSixMonths else {
            dataStorage.removeAll()
            return
        }

        calculateRetention()
    }

    func userDidSearch() {
        guard isEnabled else { return }

        
    }

    // Calculations

    /// https://app.asana.com/1/137249556945/project/1205842942115003/task/1211326699062077?focus=true
    func calculateRetention() {
        var appStarts = dataStorage.appStarts ?? AppStarts()
        appStarts.append(timestamp: Date())

        switch appStarts.timePastFromInstallation() {
        case .none:
            Logger.attribution.debug("Less than a week from installation")
            return
        case .weeks(let week):
            Logger.attribution.debug("\(week) week(s) from installation")
            let bucketedWeek = week // TODO: implement
            pixelKit.fire(AttributionPixel.userRetentionWeek(origin: originOrInstall.origin, installDate: originOrInstall.installDate, defaultBrowser: isDefaultBrowser, count: bucketedWeek), frequency: .daily)
        case .months(let month):
            Logger.attribution.debug("\(month) month(s) from installation")
            let bucketedMonth = month // TODO: implement
            pixelKit.fire(AttributionPixel.userRetentionMonth(origin: originOrInstall.origin, installDate: originOrInstall.installDate, defaultBrowser: isDefaultBrowser, count: bucketedMonth), frequency: .daily)
        }

        dataStorage.appStarts = appStarts
    }

    /// https://app.asana.com/1/137249556945/project/1205842942115003/task/1211326699062078?focus=true
    func calculateActiveSearchDays() {

    }
}

private extension Date {

    func ISO8601Format() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
