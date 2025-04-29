//
//  DuckPlayerSettings.swift
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

import BrowserServicesKit
import Combine
import Core

/// Represents the different modes for Duck Player operation.
enum DuckPlayerMode: Equatable, Codable, CustomStringConvertible, CaseIterable {
    case enabled, alwaysAsk, disabled

    private static let enabledString = "enabled"
    private static let alwaysAskString = "alwaysAsk"
    private static let neverString = "disabled"

    var description: String {
        switch self {
        case .enabled:
            return UserText.duckPlayerAlwaysEnabledLabel
        case .alwaysAsk:
            return UserText.duckPlayerAskLabel
        case .disabled:
            return UserText.duckPlayerDisabledLabel
        }
    }

    var stringValue: String {
        switch self {
        case .enabled:
            return Self.enabledString
        case .alwaysAsk:
            return Self.alwaysAskString
        case .disabled:
            return Self.neverString
        }
    }

    /// Initializes a `DuckPlayerMode` from a string value.
    ///
    /// - Parameter stringValue: The string representation of the mode.
    init?(stringValue: String) {
        switch stringValue {
        case Self.enabledString:
            self = .enabled
        case Self.alwaysAskString:
            self = .alwaysAsk
        case Self.neverString:
            self = .disabled
        default:
            return nil
        }
    }
}

/// Represents the different modes for Duck Player operation.
enum NativeDuckPlayerYoutubeMode: Equatable, Codable, CustomStringConvertible, CaseIterable {
    case auto, ask, never

    private static let autoString = "auto"
    private static let askString = "ask"
    private static let neverString = "never"

    var description: String {
        switch self {
        case .auto:
            return "Automatically"
        case .ask:
            return "Let me choose"
        case .never:
            return "Don't Show"
        }
    }

    public var stringValue: String {
        switch self {
        case .auto:
            return Self.autoString
        case .ask:
            return Self.askString
        case .never:
            return Self.neverString
        }
    }

    /// Initializes a `NativeDuckPlayerYoutubeMode` from a string value.
    ///
    /// - Parameter stringValue: The string representation of the mode.
    public init?(stringValue: String) {
        switch stringValue {
        case Self.autoString:
            self = .auto
        case Self.askString:
            self = .ask
        case Self.neverString:
            self = .never
        default:
            return nil
        }
    }
}

enum DuckPlayerVariant: Equatable, Codable, CustomStringConvertible, CaseIterable {
    case classicWeb
    case nativeOptIn
    case nativeOptOut

    private static let classicAString = "Classic (Web)"
    private static let nativeBString = "Native (Opt-in)"
    private static let nativeCString = "Native (Opt-out)"
    
    var stringValue: String {
        switch self {
        case .classicWeb:
            return Self.classicAString
        case .nativeOptIn:
            return Self.nativeBString
        case .nativeOptOut:
            return Self.nativeCString
        }
    }

    var description: String {
        switch self {
        case .classicWeb:
            return Self.classicAString
        case .nativeOptIn:
            return Self.nativeBString
        case .nativeOptOut:
            return Self.nativeCString
        }
    }

     /// Initializes a `DuckPlayerVariant` from a string value.
    ///
    /// - Parameter stringValue: The string representation of the mode.
    init?(stringValue: String) {
        switch stringValue {
        case Self.classicAString:
            self = .classicWeb
        case Self.nativeBString:
            self = .nativeOptIn
        case Self.nativeCString:
            self = .nativeOptOut
        default:
            return nil
        }
    }
}

// Custom Error privacy config settings
struct CustomErrorSettings: Codable {
    let signInRequiredSelector: String
}

/// Protocol defining the settings for Duck Player.
protocol DuckPlayerSettings: AnyObject {

    /// Publisher that emits when Duck Player settings change.
    var duckPlayerSettingsPublisher: AnyPublisher<Void, Never> { get }

    /// The current mode of Duck Player.
    var mode: DuckPlayerMode { get set }

    /// Indicates if the "Always Ask" overlay has been hidden.
    var askModeOverlayHidden: Bool { get set }

    /// Flag to allow the first video to play in Youtube
    var allowFirstVideo: Bool { get set }

    /// Determines if Duck Player should open videos in a new tab.
    var openInNewTab: Bool { get set }

    /// Determines if the native UI should be used
    var nativeUI: Bool { get set }

    /// Determines if the native UI should be used for SERP
    var nativeUISERPEnabled: Bool { get set }

    /// Determines if the native UI should be used for Youtube
    var nativeUIYoutubeMode: NativeDuckPlayerYoutubeMode { get set }

    /// Determines if the priming modal has been presented
    var nativeUIPrimingModalPresentedCount: Int { get }

    /// Determines the number of seconds since the last priming modal was presented
    var duckPlayerNativeUIPrimingModalTimeSinceLastPresented: Int { get }

    /// Autoplay Videos when opening
    var autoplay: Bool { get set }

    // Determines if we should show a custom view when YouTube returns an error
    var customError: Bool { get }

    // Holds additional configuration for the custom error view
    var customErrorSettings: CustomErrorSettings? { get }

    var variant: DuckPlayerVariant { get set }

    /// Initializes a new instance with the provided app settings and privacy configuration manager.
    ///
    /// - Parameters:
    ///   - appSettings: The application settings.
    ///   - privacyConfigManager: The privacy configuration manager.
    init(appSettings: AppSettings, privacyConfigManager: PrivacyConfigurationManaging, internalUserDecider: InternalUserDecider)

    /// Triggers a notification to update subscribers about settings changes.
    func triggerNotification()
}

/// Default implementation of `DuckPlayerSettings`.
final class DuckPlayerSettingsDefault: DuckPlayerSettings {

    private var appSettings: AppSettings
    private let privacyConfigManager: PrivacyConfigurationManaging
    private var isFeatureEnabledCancellable: AnyCancellable?
    private var internalUserDecider: InternalUserDecider

    private var _isFeatureEnabled: Bool
    private var isFeatureEnabled: Bool {
        get {
            return _isFeatureEnabled
        }
        set {
            if _isFeatureEnabled != newValue {
                _isFeatureEnabled = newValue
                duckPlayerSettingsSubject.send()
            }
        }
    }

    private let duckPlayerSettingsSubject = PassthroughSubject<Void, Never>()
    var duckPlayerSettingsPublisher: AnyPublisher<Void, Never> {
        duckPlayerSettingsSubject.eraseToAnyPublisher()
    }

    /// Initializes a new instance with the provided app settings and privacy configuration manager.
    ///
    /// - Parameters:
    ///   - appSettings: The application settings.
    ///   - privacyConfigManager: The privacy configuration manager.
    init(appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         privacyConfigManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         internalUserDecider: InternalUserDecider = AppDependencyProvider.shared.internalUserDecider) {
        self.appSettings = appSettings
        self.privacyConfigManager = privacyConfigManager
        self._isFeatureEnabled = privacyConfigManager.privacyConfig.isEnabled(featureKey: .duckPlayer)
        self.internalUserDecider = internalUserDecider
        registerConfigPublisher()
        registerForNotificationChanges()
    }

    /// DuckPlayer features are only available in these domains
    public struct OriginDomains {
        static let duckduckgo = "duckduckgo.com"
        static let youtubeWWW = "www.youtube.com"
        static let youtube = "youtube.com"
        static let youtubeMobile = "m.youtube.com"
    }

    /// The current mode of Duck Player.
    var mode: DuckPlayerMode {
        get {
            guard isFeatureEnabled else { return .disabled }
            // Return the underlying setting, reflecting user choice or variant default
            return appSettings.duckPlayerMode
        }
        set {
            // Allow direct setting if needed, but primarily managed by variant
            if newValue != appSettings.duckPlayerMode {
                appSettings.duckPlayerMode = newValue
                triggerNotification()
            }
        }
    }

    /// Indicates if the "Always Ask" overlay has been hidden.
    var askModeOverlayHidden: Bool {
        get {
            if isFeatureEnabled {
                return appSettings.duckPlayerAskModeOverlayHidden
            } else {
                return false
            }
        }
        set {
            if newValue != appSettings.duckPlayerAskModeOverlayHidden {
                appSettings.duckPlayerAskModeOverlayHidden = newValue
                triggerNotification()
            }
        }
    }
    

    /// Flag to allow the first video to play without redirection.
    var allowFirstVideo: Bool = false

    /// Determines if Duck Player should open videos in a new tab.
    var openInNewTab: Bool {
        get {
            // Return the underlying AppSetting value directly
            return appSettings.duckPlayerOpenInNewTab
        }
        set {
            // Allow direct setting if needed, potentially overridden by variant change
            if newValue != appSettings.duckPlayerOpenInNewTab {
                appSettings.duckPlayerOpenInNewTab = newValue
                triggerNotification()
            }
        }
    }

    // Determines if we should use the native verion of DuckPlayer (Internal only)
    var nativeUI: Bool {
        get {
            guard internalUserDecider.isInternalUser, UIDevice.current.userInterfaceIdiom == .phone else { return false }
            return appSettings.duckPlayerNativeUI
        }
        set {
             // Allow direct setting if needed, potentially overridden by variant change
            if newValue != appSettings.duckPlayerNativeUI {
                appSettings.duckPlayerNativeUI = newValue
                triggerNotification()
            }
        }
    }

    // Determines if DuckPlayer Native is enabled for SERP
    var nativeUISERPEnabled: Bool {
        get {
            guard internalUserDecider.isInternalUser, UIDevice.current.userInterfaceIdiom == .phone else { return false }
            return appSettings.duckPlayerNativeUI && appSettings.duckPlayerNativeUISERPEnabled
        }
        set {
            if newValue != appSettings.duckPlayerNativeUISERPEnabled {
                appSettings.duckPlayerNativeUISERPEnabled = newValue
                triggerNotification()
            }
        }
    }

    // Determines the Youtube mode for DuckPlayer Native
    var nativeUIYoutubeMode: NativeDuckPlayerYoutubeMode {
        get {
            guard isFeatureEnabled else { return .never }
            // Return the underlying AppSetting value
            return appSettings.duckPlayerNativeYoutubeMode
        }
        set {
            // Allow direct setting if needed, potentially overridden by variant change
            if newValue != appSettings.duckPlayerNativeYoutubeMode {
                appSettings.duckPlayerNativeYoutubeMode = newValue
                triggerNotification()
            }
        }
    }

    /// Determines if the priming modal has been presented
    var nativeUIPrimingModalPresentedCount: Int { return appSettings.duckPlayerNativeUIPrimingModalPresentationEventCount }

    /// Determines the number of seconds since the last priming modal was presented
    var duckPlayerNativeUIPrimingModalTimeSinceLastPresented: Int { return appSettings.duckPlayerNativeUIPrimingModalLastPresentationTime }

    // Determines if we should use the native verion of DuckPlayer (Internal only)
    var autoplay: Bool {
        get {
            guard internalUserDecider.isInternalUser, UIDevice.current.userInterfaceIdiom == .phone else { return false }
            return appSettings.duckPlayerAutoplay
        }
        set {
            if newValue != appSettings.duckPlayerAutoplay {
                appSettings.duckPlayerAutoplay = newValue
                triggerNotification()
            }
        }
    }
    // Determines if we should show a custom view when YouTube returns an error
    var customError: Bool {
        return privacyConfigManager.privacyConfig.isSubfeatureEnabled(DuckPlayerSubfeature.customError)
    }

    // Holds additional configuration for the custom error view
    var customErrorSettings: CustomErrorSettings? {
        let decoder = JSONDecoder()

        if let customErrorSettingsJSON = privacyConfigManager.privacyConfig.settings(for: DuckPlayerSubfeature.customError),
           let jsonData = customErrorSettingsJSON.data(using: .utf8) {
            do {
                let customErrorSettings = try decoder.decode(CustomErrorSettings.self, from: jsonData)
                return customErrorSettings
            } catch {
                return nil
            }
        }
        return nil
    }

    var variant: DuckPlayerVariant {
        get {
            return appSettings.duckPlayerVariant
        }
        set {
            if newValue != appSettings.duckPlayerVariant {
                appSettings.duckPlayerVariant = newValue

                // Apply specific settings based on the new variant
                switch newValue {
                case .classicWeb:
                    // Set Classic A specific settings
                    self.nativeUI = false
                    self.nativeUISERPEnabled = false
                    self.mode = .alwaysAsk
                    self.nativeUIYoutubeMode = .never
                    self.openInNewTab = true
                    self.autoplay = false

                case .nativeOptIn:
                    // Set Native B specific settings
                    self.nativeUI = true
                    self.nativeUISERPEnabled = true
                    // mode remains unchanged (Only used in classicA)
                    self.nativeUIYoutubeMode = .ask
                    // openInNewTab remains unchanged (Only used in classicA)
                    self.autoplay = true

                case .nativeOptOut:
                    // Set Native C specific settings
                    self.nativeUI = true
                    self.nativeUISERPEnabled = true
                    // mode remains unchanged (Only used in classicA)
                    self.nativeUIYoutubeMode = .auto
                    // openInNewTab remains unchanged (Only used in classicA)
                    self.autoplay = true
                }
                
            }
        }
    }

    /// Registers a publisher to listen for changes in the privacy configuration.
    private func registerConfigPublisher() {
        isFeatureEnabledCancellable = privacyConfigManager.updatesPublisher
            .map { [weak privacyConfigManager] in
                privacyConfigManager?.privacyConfig.isEnabled(featureKey: .duckPlayer) == true
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.isFeatureEnabled = isEnabled
            }
    }

    /// Registers for notification changes in Duck Player settings.
    private func registerForNotificationChanges() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(publishUpdate),
                                               name: AppUserDefaults.Notifications.duckPlayerSettingsUpdated,
                                               object: nil)
    }

    /// Publishes an update notification when settings change.
    ///
    /// - Parameter notification: The notification received.
    @objc private func publishUpdate(_ notification: Notification) {
        triggerNotification()
    }

    /// Triggers a notification to update subscribers about settings changes.
    func triggerNotification() {
        duckPlayerSettingsSubject.send()
    }

    deinit {
        isFeatureEnabledCancellable?.cancel()
        NotificationCenter.default.removeObserver(self, name: AppUserDefaults.Notifications.duckPlayerSettingsUpdated, object: nil)
    }
}
