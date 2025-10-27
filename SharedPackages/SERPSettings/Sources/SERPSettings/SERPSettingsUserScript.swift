//
//  SERPSettingsUserScript.swift
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

import Common
import UserScript
import Foundation
import WebKit
#if os(macOS)
import Combine
#endif

// MARK: - UserScript Messages

/// Messages that can be exchanged between SERP and native application.
///
/// This enum defines the complete messaging protocol for SERP settings
/// synchronization, including both SERP-to-native and native-to-SERP messages.
public enum SERPSettingsUserScriptMessages: String, CaseIterable {

    /// Request from SERP to open native settings screens.
    ///
    /// **Direction**: SERP → Native
    ///
    /// The SERP sends this message when the user clicks a link to navigate
    /// to native settings (e.g., Privacy Search, AI Features).
    ///
    /// **Parameters**: Dictionary with `"return"` or `"screen"` keys
    case openNativeSettings

    /// Notification from SERP that settings have changed.
    ///
    /// **Direction**: SERP → Native
    ///
    /// The SERP sends the complete current settings state whenever any
    /// setting changes. Native stores this as the new source of truth.
    ///
    /// **Parameters**: Dictionary of all non-default setting key-value pairs
    case updateNativeSettings

    /// Request from SERP for current native settings.
    ///
    /// **Direction**: SERP → Native
    ///
    /// The SERP requests stored settings when the page loads, allowing
    /// it to initialize with previously saved user preferences.
    ///
    /// **Response**: JSONBlob containing stored settings, or null.
    case getNativeSettings

    /// Notification from native that Duck.ai setting changed.
    ///
    /// **Direction**: Native → SERP
    ///
    /// The native app pushes this message when the AI features toggle
    /// changes outside of SERP (e.g., in app settings).
    ///
    /// **Parameters**: Boolean value of `isAIChatEnabled`
    case nativeDuckAiSettingChanged

    /// Request from SERP for current Duck.ai enabled state.
    ///
    /// **Direction**: SERP → Native
    ///
    /// The SERP queries the current state of AI features to determine
    /// which UI elements should be displayed.
    ///
    /// **Response**: Boolean value of `isAIChatEnabled`
    case isNativeDuckAiEnabled
}

public final class SERPSettingsUserScript: NSObject, Subfeature {

    // MARK: - Properties

    /// Message broker for UserScript communication.
    ///
    /// The broker handles message delivery between JavaScript and native code.
    public weak var broker: UserScriptMessageBroker?

    /// Delegate for handling navigation and settings screen requests.
    ///
    /// The delegate is responsible for presenting native settings screens
    /// when requested by the SERP.
    public weak var delegate: SERPSettingsUserScriptDelegate?

    /// WebView associated with this user script instance.
    ///
    /// Required for pushing messages from native to SERP
    /// (e.g., AI settings changes).
    public weak var webView: WKWebView?

    /// Security policy for message origin validation.
    ///
    /// Ensures messages are only accepted from trusted SERP domains.
    public var messageOriginPolicy: MessageOriginPolicy

    /// Identifier for this user script feature.
    ///
    /// Used by the UserScript framework for feature identification
    /// and message routing.
    public let featureName: String = "serpSettings"

    /// Settings provider for storage and retrieval operations.
    ///
    /// Handles the actual persistence, platform-specific AI state queries,
    /// and feature flag checks.
    private let serpSettingsProviding: SERPSettingsProviding

#if os(macOS)
    /// Combine cancellable for AI features publisher subscription.
    ///
    /// Stores the subscription to the AI preferences storage publisher,
    /// ensuring the subscription remains active for the lifetime of this user script.
    private var aiFeaturesCancellable: AnyCancellable?
#endif

    // MARK: - Initialization

    public init(serpSettingsProviding: SERPSettingsProviding) {
        self.serpSettingsProviding = serpSettingsProviding
        self.messageOriginPolicy = .only(rules: serpSettingsProviding.buildMessageOriginRules())
        super.init()

        setupAISettingsObserver()
    }

    // MARK: - AI Settings Observer Setup

    /// Sets up observation of AI settings changes.
    ///
    /// This method configures platform-specific subscriptions to be notified
    /// when the AI features setting changes in native preferences.
    ///
    /// - **macOS**: Uses Combine publisher from `AIChatPreferencesStorage`
    /// - **iOS**: Uses NotificationCenter with `.aiChatSettingsChanged` notification
    private func setupAISettingsObserver() {
        #if os(macOS)
        // Subscribe to AI features changes via Combine publisher
        aiFeaturesCancellable = serpSettingsProviding.aiChatPreferencesStorage.isAIFeaturesEnabledPublisher
            .dropFirst() // Skip the initial value to avoid unnecessary message on startup
            .sink { [weak self] _ in
                self?.nativeDuckAiSettingChanged()
            }
        #elseif os(iOS)
        // Subscribe to AI features changes via NotificationCenter
        NotificationCenter.default.addObserver(
            forName: .aiChatSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.nativeDuckAiSettingChanged()
        }
        #endif
    }

    // MARK: - Subfeature

    /// Registers this user script with a message broker.
    ///
    /// - Parameter broker: The broker to use for message handling
    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    /// Returns the message handler for a given method name.
    ///
    /// Maps message names to their corresponding handler methods.
    /// Returns `nil` for unsupported or native-only messages.
    ///
    /// - Parameter methodName: Name of the message to handle
    /// - Returns: Handler function if supported, `nil` otherwise
    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = SERPSettingsUserScriptMessages(rawValue: methodName) else {
            return nil
        }

        switch message {
        case .openNativeSettings:
            return openNativeSettings
        case .updateNativeSettings:
            return updateNativeSettings
        case .getNativeSettings:
            return getNativeSettings
        case .isNativeDuckAiEnabled:
            return isNativeDuckAiEnabled
        case .nativeDuckAiSettingChanged:
            // This message is sent FROM native TO SERP, never handled as incoming
            return nil
        }
    }

    // MARK: - SERP to Native Communication

    /// Handles request for stored SERP settings.
    ///
    /// Called when the SERP page loads and needs to initialize with stored settings.
    ///
    ///
    /// - Parameters:
    ///   - params: Unused parameters from the message
    ///   - message: The message context
    /// - Returns: JSONBlob containing stored settings, or `nil` if feature is disabled
    @MainActor
    private func getNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        // Feature flag check - allows disabling the feature remotely
        guard serpSettingsProviding.isSERPSettingsFeatureOn() else {
            return nil
        }

        return serpSettingsProviding.getSERPSettings()
    }

    /// Handles settings update from SERP.
    ///
    /// Called whenever the user changes a setting on the SERP. The SERP sends
    /// the complete state of all non-default settings.
    ///
    /// ## Storage Strategy
    ///
    /// The incoming settings dictionary contains **only** non-default values.
    /// This allows the SERP to update defaults without requiring native migration.
    /// Missing keys indicate the user has not changed that setting from the default.
    ///
    /// - Parameters:
    ///   - params: Dictionary of setting key-value pairs
    ///   - message: The message context
    /// - Returns: Always returns `nil` (no response needed)
    @MainActor
    private func updateNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        // Feature flag check
        guard serpSettingsProviding.isSERPSettingsFeatureOn() else {
            return nil
        }

        // Validate parameters are a dictionary
        guard let settings = params as? [String: Any] else { return nil }

        // Store settings (replaces previous state entirely)
        serpSettingsProviding.storeSERPSettings(settings: settings)

        return nil
    }

    /// Handles request to open native settings screens.
    ///
    /// Called when the user clicks a link on the SERP to navigate to native settings.
    /// Delegates to the app to present the appropriate settings screen.
    ///
    /// ## Supported Screens
    ///
    /// - **Privacy Search**: Settings for private search features
    /// - **AI Features**: Settings for Duck.ai and AI-powered features
    ///
    /// ## Parameter Format
    ///
    /// The parameters dictionary can contain:
    /// - `"return": "privateSearch"` - Navigate to privacy settings
    /// - `"return": "aiFeatures"` - Navigate to AI settings after closing tab
    /// - `"screen": "aiFeatures"` - Navigate directly to AI settings
    ///
    /// - Parameters:
    ///   - params: Dictionary specifying which screen to open
    ///   - message: The message context
    /// - Returns: Always returns `nil` (no response needed)
    @MainActor
    private func openNativeSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let parameters = params as? [String: String] else { return nil }

        // Check "return" parameter for navigation after closing tab
        if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.privateSearch {
            delegate?.serpSettingsUserScriptDidRequestToOpenPrivacySettings(self)
        } else if parameters[SERPSettingsConstants.returnParameterKey] == SERPSettingsConstants.aiFeatures {
            delegate?.serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(self)
        }
        // Check "screen" parameter for direct navigation
        else if parameters[SERPSettingsConstants.screenParameterKey] == SERPSettingsConstants.aiFeatures {
            delegate?.serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(self)
        }

        return nil
    }

    /// Returns the current state of Duck.ai features.
    ///
    /// Called by the SERP to determine if AI-powered features should be displayed.
    /// The value reflects the user's preference in native settings.
    ///
    /// - Parameters:
    ///   - params: Unused parameters
    ///   - message: The message context
    /// - Returns: Boolean indicating if AI chat is enabled
    @MainActor
    private func isNativeDuckAiEnabled(params: Any, message: UserScriptMessage) -> Encodable? {
        return NativeDuckAIState(enabled: serpSettingsProviding.isAIChatEnabled)
    }

    // MARK: - Native to SERP Communication

    /// Notifies the SERP that the Duck.ai setting has changed.
    ///
    /// This method pushes a message to the SERP when the AI features toggle
    /// is changed in native settings. This allows the SERP to update its UI
    /// in real-time without requiring a page reload.
    ///
    /// ## Automatic Invocation
    ///
    /// This method is automatically called when the AI features setting changes:
    /// - **macOS**: Triggered by Combine publisher subscription to `isAIFeaturesEnabledPublisher`
    /// - **iOS**: Triggered by NotificationCenter observer for `.aiChatSettingsChanged`
    ///
    /// The subscription is set up in `setupAISettingsObserver()` during initialization.
    func nativeDuckAiSettingChanged() {
        guard let webView else {
            return
        }

        broker?.push(method: SERPSettingsUserScriptMessages.nativeDuckAiSettingChanged.rawValue,
                     params: NativeDuckAIState(enabled: serpSettingsProviding.isAIChatEnabled),
                     for: self,
                     into: webView)
    }

    // MARK: - Cleanup

    deinit {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }
}

// MARK: - Notification Names

#if os(iOS)
public extension Notification.Name {
    /// Notification posted when AI Chat settings change on iOS.
    ///
    /// This notification should be posted by the iOS app whenever the AI features
    /// setting is toggled in preferences, allowing SERP to be notified of the change.
    static let aiChatSettingsChanged = Notification.Name("com.duckduckgo.aichat.settings.changed")
}
#endif


/// Model that holds the state of the Duck.ai state
/// Needed for sending/receiving between SERP and Native.
private struct NativeDuckAIState: Encodable {
    let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }
}
