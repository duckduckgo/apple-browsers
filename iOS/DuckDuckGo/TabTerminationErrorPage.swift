//
//  TabTerminationErrorPage.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PixelKit
import PrivacyConfig
import UIKit

protocol TabTerminationErrorPageInstrumenting {
    func errorPageShown()
    func reloadSelected()
    func sendFeedbackSelected()
}

final class DefaultTabTerminationErrorPageInstrumentation: TabTerminationErrorPageInstrumenting {

    private let pixelFiring: (any PixelFiring)?

    init(pixelFiring: (any PixelFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func errorPageShown() {
        pixelFiring?.fire(TabTerminationErrorPagePixel.shown, frequency: .dailyAndCount)
    }

    func reloadSelected() {
        pixelFiring?.fire(TabTerminationErrorPagePixel.reload, frequency: .dailyAndCount)
    }

    func sendFeedbackSelected() {
        pixelFiring?.fire(TabTerminationErrorPagePixel.sendFeedback, frequency: .dailyAndCount)
    }
}

enum TabTerminationErrorPagePixel: PixelKitEvent, PixelKitEventWithCustomPrefix {
    case shown
    case reload
    case sendFeedback

    var name: String {
        switch self {
        case .shown:
            return "tab-termination_error-page_shown"
        case .reload:
            return "tab-termination_error-page_reload"
        case .sendFeedback:
            return "tab-termination_error-page_send-feedback"
        }
    }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: String { "" }
}

struct TabTerminationErrorPageSettings {

    enum FormFactor: String, CaseIterable {
        case phone
        case tablet
    }

    private enum Constants {
        static let defaultTerminationCount = 3
        static let defaultTimeWindow: TimeInterval = 60
        static let terminationCountKey = "terminationCount"
        static let supportedFormFactorsKey = "supportedFormFactors"
        static let timeWindowSecondsKey = "timeWindowSeconds"
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    var terminationCount: Int {
        guard let number = number(forKey: Constants.terminationCountKey),
              number.doubleValue.rounded() == number.doubleValue,
              number.intValue > 0 else {
            return Constants.defaultTerminationCount
        }
        return number.intValue
    }

    var timeWindow: TimeInterval {
        guard let number = number(forKey: Constants.timeWindowSecondsKey),
              number.doubleValue > 0 else {
            return Constants.defaultTimeWindow
        }
        return number.doubleValue
    }

    var supportedFormFactors: Set<FormFactor> {
        guard let values = value(forKey: Constants.supportedFormFactorsKey) as? [String] else {
            return Set(FormFactor.allCases)
        }
        return Set(values.compactMap(FormFactor.init(rawValue:)))
    }

    private func number(forKey key: String) -> NSNumber? {
        guard let value = value(forKey: key),
              !(value is Bool) else {
            return nil
        }
        return value as? NSNumber
    }

    private func value(forKey key: String) -> Any? {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: iOSBrowserConfigSubfeature.tabTerminationErrorPage),
              let data = json.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dictionary[key] else {
            return nil
        }
        return value
    }
}

@MainActor
protocol TabTerminationErrorPageDetecting {
    func shouldShowErrorPage(forTabID tabID: String) -> Bool
    func removeHistory(forTabID tabID: String)
}

@MainActor
final class TabTerminationErrorPageDetector: TabTerminationErrorPageDetecting {

    private let featureFlagger: FeatureFlagger
    private let settings: TabTerminationErrorPageSettings
    private let formFactor: TabTerminationErrorPageSettings.FormFactor
    private let date: () -> Date
    private var terminationDatesByTabID: [String: [Date]] = [:]

    init(featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         formFactor: TabTerminationErrorPageSettings.FormFactor = UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone,
         date: @escaping () -> Date = Date.init) {
        self.featureFlagger = featureFlagger
        self.settings = TabTerminationErrorPageSettings(privacyConfigurationManager: privacyConfigurationManager)
        self.formFactor = formFactor
        self.date = date
    }

    func shouldShowErrorPage(forTabID tabID: String) -> Bool {
        guard featureFlagger.isFeatureOn(.tabTerminationErrorPage),
              settings.supportedFormFactors.contains(formFactor) else {
            terminationDatesByTabID[tabID] = nil
            return false
        }

        let terminationDate = date()
        let timeWindow = settings.timeWindow
        var terminationDates = terminationDatesByTabID[tabID, default: []]
        terminationDates.removeAll { terminationDate.timeIntervalSince($0) > timeWindow }
        terminationDates.append(terminationDate)
        terminationDatesByTabID[tabID] = terminationDates
        return terminationDates.count >= settings.terminationCount
    }

    func removeHistory(forTabID tabID: String) {
        terminationDatesByTabID[tabID] = nil
    }
}
