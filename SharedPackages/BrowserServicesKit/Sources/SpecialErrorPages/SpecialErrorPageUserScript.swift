//
//  SpecialErrorPageUserScript.swift
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
import UserScript
import WebKit
import Common
import Combine

public protocol SpecialErrorPageUserScriptDelegate: AnyObject {

    @MainActor var errorData: SpecialErrorData? { get }

    @MainActor func leaveSiteAction()
    @MainActor func visitSiteAction()
    @MainActor func advancedInfoPresented()

}

struct LocalizedInfo: Encodable, Equatable {
    let title: String
    let note: String
}

public final class SpecialErrorPageUserScript: NSObject, Subfeature {

    enum MessageName: String, CaseIterable {
        case initialSetup
        case reportPageException
        case reportInitException
        case leaveSite
        case visitSite
        case advancedInfo
        case onThemeUpdate
    }

    struct ThemeUpdate: Encodable {
        let theme: String
        let themeVariant: String
    }

    public let messageOriginPolicy: MessageOriginPolicy = .all
    public let featureName: String = "special-error"

    public var isEnabled: Bool = false

    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: SpecialErrorPageUserScriptDelegate?
    public weak var webView: WKWebView?

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    private let localeStrings: String?
    private let languageCode: String
    private var styleCancellable: AnyCancellable?
    private let styleProvider: ScriptStyleProviding?

    public init(localeStrings: String?, languageCode: String, styleProvider: ScriptStyleProviding? = nil) {
        self.localeStrings = localeStrings
        self.languageCode = languageCode
        self.styleProvider = styleProvider

        super.init()

        subscribeToThemeChangesIfPossible(styleProvider: styleProvider)
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard isEnabled else { return nil }

        switch MessageName(rawValue: methodName) {
        case .initialSetup: return initialSetup
        case .reportPageException: return reportPageException
        case .reportInitException: return reportInitException
        case .leaveSite: return handleLeaveSiteAction
        case .visitSite: return handleVisitSiteAction
        case .advancedInfo: return handleAdvancedInfoPresented
        default:
            assertionFailure("SpecialErrorPageUserScript: Failed to parse User Script message: \(methodName)")
            return nil
        }
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) async throws -> Encodable? {
#if DEBUG
        let env = "development"
#else
        let env = "production"
#endif

#if os(iOS)
        let platform = Platform(name: "ios")
#else
        let platform = Platform(name: "macos")
#endif
        guard let errorData = delegate?.errorData else { return nil }
        return InitialSetupResult(env: env,
                                  locale: languageCode,
                                  localeStrings: localeStrings,
                                  platform: platform,
                                  errorData: errorData,
                                  theme: styleProvider?.themeAppearance,
                                  themeVariant: styleProvider?.themeName)
    }

    @MainActor
    func handleLeaveSiteAction(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.leaveSiteAction()
        return nil
    }

    @MainActor
    func handleVisitSiteAction(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.visitSiteAction()
        return nil
    }

    @MainActor
    func handleAdvancedInfoPresented(params: Any, message: UserScriptMessage) -> Encodable? {
        delegate?.advancedInfoPresented()
        return nil
    }

    @MainActor
    private func reportInitException(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return nil
    }

    @MainActor
    private func reportPageException(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return nil
    }

}

private extension SpecialErrorPageUserScript {

    func subscribeToThemeChangesIfPossible(styleProvider: ScriptStyleProviding?) {
        styleCancellable = styleProvider?.themeStylePublisher
            .sink { [weak self] appearance, themeName in
                Task { @MainActor in
                    self?.notifyThemeStyle(appearance: appearance, themeName: themeName)
                }
            }
    }

    @MainActor
    private func notifyThemeStyle(appearance: String, themeName: String) {
        guard let broker, let webView else {
            return
        }

        let payload = ThemeUpdate(theme: appearance, themeVariant: themeName)
        broker.push(method: MessageName.onThemeUpdate.rawValue, params: payload, for: self, into: webView)
    }
}

extension SpecialErrorPageUserScript {

    struct Platform: Encodable, Equatable {

        let name: String

    }

    struct InitialSetupResult: Encodable, Equatable {
        let env: String
        let locale: String
        let localeStrings: String?
        let platform: Platform
        let errorData: SpecialErrorData
        let theme: String?
        let themeVariant: String?

        enum CodingKeys: String, CodingKey {
            case env
            case locale
            case localeStrings
            case platform
            case errorData
            case theme
            case themeVariant
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(env, forKey: .env)
            try container.encode(locale, forKey: .locale)
            try container.encode(localeStrings, forKey: .localeStrings)
            try container.encode(platform, forKey: .platform)
            try container.encode(errorData, forKey: .errorData)

            // We're explicitly skipping Theme / ThemeVariant as they're currently not in use in iOS
            try container.encodeIfPresent(theme, forKey: .theme)
            try container.encodeIfPresent(themeVariant, forKey: .themeVariant)
        }
    }
}
