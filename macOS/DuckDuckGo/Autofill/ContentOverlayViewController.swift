//
//  ContentOverlayViewController.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AutofillResources
import BrowserServicesKit
import Cocoa
import Combine
import Common
import PixelKit
import SecureStorage
import WebKit
import enum UserScript.UserScriptError

@MainActor
public final class ContentOverlayViewController: NSViewController, EmailManagerRequestDelegate {

    @IBOutlet var webView: WKWebView!
    private var topAutofillUserScript: OverlayAutofillUserScript?
    private var appearanceCancellable: AnyCancellable?

    public weak var autofillInterfaceToChild: OverlayAutofillUserScriptDelegate?

    lazy var emailManager: EmailManager = {
        let emailManager = EmailManager()
        emailManager.requestDelegate = self
        return emailManager
    }()

    lazy var vaultManager: SecureVaultManager = {
        let manager = SecureVaultManager(passwordManager: PasswordManagerCoordinator.shared,
                                         shouldAllowPartialFormSaves: featureFlagger.isFeatureOn(.autofillPartialFormSaves),
                                         tld: tld)
        manager.delegate = self
        return manager
    }()

    lazy var credentialsImportManager: AutofillCredentialsImportManager = {
        let manager = AutofillCredentialsImportManager(isBurnerWindow: false)
        manager.presentationDelegate = self
        return manager
    }()

    lazy var autofillPreferencesModel: AutofillPreferencesModel = {
        let model = AutofillPreferencesModel()
        return model
    }()

    init?(
        coder: NSCoder,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        featureFlagger: FeatureFlagger,
        tld: TLD
    ) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.featureFlagger = featureFlagger
        self.tld = tld
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    lazy var passwordManagerCoordinator: PasswordManagerCoordinating = PasswordManagerCoordinator.shared

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let featureFlagger: FeatureFlagger
    private let tld: TLD

    lazy var usageProvider: AutofillUsageProvider = AutofillUsageStore(standardUserDefaults: .standard, appGroupUserDefaults: nil)

    public override func viewDidLoad() {
        initWebView()
        addTrackingArea()

        appearanceCancellable = NSApp.publisher(for: \.effectiveAppearance).map { $0 as NSAppearance? }.sink { [weak self] appearance in
            self?.webView.appearance = appearance
        }

        // Initialize to default size to reduce flicker
        requestResizeToSize(CGSize(width: 0, height: 0))
    }

    public func setType(serializedInputContext: String, zoomFactor: CGFloat?) {
        guard let topAutofillUserScript = topAutofillUserScript else { return }
        if let zoomFactor = zoomFactor {
            initWebView()
            webView.magnification = zoomFactor
        }
        topAutofillUserScript.serializedInputContext = serializedInputContext
    }

    public override func mouseMoved(with event: NSEvent) {
        // Change to flipped coordinate system
        let outY = webView.frame.height - event.locationInWindow.y
        messageMouseMove(x: event.locationInWindow.x, y: outY)
    }

    private func addTrackingArea() {
        let trackingOptions: NSTrackingArea.Options = [ .activeInActiveApp,
                                                        .enabledDuringMouseDrag,
                                                        .mouseMoved,
                                                        .inVisibleRect ]
        let trackingArea = NSTrackingArea(rect: webView.frame, options: trackingOptions, owner: self, userInfo: nil)
        webView.addTrackingArea(trackingArea)
    }

    public override func viewWillAppear() {
        guard let topAutofillUserScript = topAutofillUserScript else { return }
        topAutofillUserScript.websiteAutofillInstance = autofillInterfaceToChild

        webView.appearance = NSApp.effectiveAppearance

        let url = AutofillResources.bundle.url(forResource: "TopAutofill", withExtension: "html")
        if let url = url {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }
    }

    public override func viewWillDisappear() {
        // We should never see this but it's better than a flash of old content
        webView.load(URLRequest(url: .blankPage))
    }

    public func messageMouseMove(x: CGFloat, y: CGFloat) {
        // Fakes the elements being focused by the user as it doesn't appear there's much else we can do
        let script = """
        (() => {
        const x = \(x);
        const y = \(y);
        window.dispatchEvent(new CustomEvent('mouseMove', {detail: {x, y}}))
        })();
        """
        webView.evaluateJavaScript(script)
    }

    public func buildAutofillSource() -> AutofillUserScriptSourceProvider {
        let scriptSourceProviding = DefaultScriptSourceProvider()
        return scriptSourceProviding.buildAutofillSource()
    }

    private func initWebView() {
        let scriptSourceProvider = buildAutofillSource()
        self.topAutofillUserScript = OverlayAutofillUserScript(scriptSourceProvider: scriptSourceProvider, overlay: self)
        guard let topAutofillUserScript = topAutofillUserScript else { return }
        let configuration = WKWebViewConfiguration()
        let debugScriptEnabled = AutofillPreferences().debugScriptEnabled
        configuration.preferences.setValue(debugScriptEnabled, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsLinkPreview = false
        webView.window?.acceptsMouseMovedEvents = true
        webView.window?.ignoresMouseEvents = false
        webView.configuration.userContentController.addHandler(topAutofillUserScript)
        webView.configuration.userContentController.addUserScript(topAutofillUserScript.makeWKUserScriptSync())
        if #available(macOS 13.3, *) {
            webView.isInspectable = debugScriptEnabled
        }
        self.webView = webView
        view.addAndLayout(webView)
        topAutofillUserScript.contentOverlay = self
        topAutofillUserScript.emailDelegate = emailManager
        topAutofillUserScript.vaultDelegate = vaultManager
        topAutofillUserScript.passwordImportDelegate = credentialsImportManager
    }

    // EmailManagerRequestDelegate

    nonisolated
    public func emailManager(_ emailManager: EmailManager,
                             requested url: URL,
                             method: String,
                             headers: [String: String],
                             parameters: [String: String]?,
                             httpBody: Data?,
                             timeoutInterval: TimeInterval) async throws -> Data {
        let finalURL = url.appendingParameters(parameters ?? [:])

        var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
        request.allHTTPHeaderFields = headers
        request.httpMethod = method
        request.httpBody = httpBody

        return try await URLSession.shared.data(for: request).0
    }

    nonisolated
    public func emailManagerKeychainAccessFailed(_ emailManager: EmailManager, accessType: EmailKeychainAccessType, error: EmailKeychainAccessError) {
        var parameters = [
            "access_type": accessType.rawValue,
            "error": error.errorDescription
        ]

        if case let .keychainLookupFailure(status) = error {
            parameters["keychain_status"] = String(status)
            parameters["keychain_operation"] = "lookup"
        }

        if case let .keychainDeleteFailure(status) = error {
            parameters["keychain_status"] = String(status)
            parameters["keychain_operation"] = "delete"
        }

        if case let .keychainSaveFailure(status) = error {
            parameters["keychain_status"] = String(status)
            parameters["keychain_operation"] = "save"
        }

        PixelKit.fire(DebugEvent(GeneralPixel.emailAutofillKeychainError), withAdditionalParameters: parameters)
    }

    private enum Constants {
        static let minWidth: CGFloat = 315
        static let minHeight: CGFloat = 56
    }

    public func requestResizeToSize(_ size: CGSize) {
        var widthOut = size.width
        if widthOut < Constants.minWidth {
            widthOut = Constants.minWidth
        }
        var heightOut = size.height
        if heightOut < Constants.minHeight {
            heightOut = Constants.minHeight
        }
        self.preferredContentSize = CGSize(width: widthOut, height: heightOut)
    }

}

extension ContentOverlayViewController: OverlayAutofillUserScriptPresentationDelegate {
    public func overlayAutofillUserScript(_ overlayAutofillUserScript: OverlayAutofillUserScript, requestResizeToSize: CGSize) {
        self.requestResizeToSize(requestResizeToSize)
    }

    public func closeContentOverlayPopover() {
        self.topAutofillUserScript?.closeAutofillParent()
    }
}

extension ContentOverlayViewController: SecureVaultManagerDelegate {

    public func secureVaultManagerIsEnabledStatus(_ manager: SecureVaultManager, forType type: AutofillType?) -> Bool {
        let prefs = AutofillPreferences()
        switch type {
        case .card:
            return prefs.askToSavePaymentMethods
        case .identity:
            return prefs.askToSaveAddresses
        case.password:
            return prefs.askToSaveUsernamesAndPasswords
        case .none:
            return prefs.askToSaveAddresses || prefs.askToSavePaymentMethods || prefs.askToSaveUsernamesAndPasswords
        }
    }
    public func secureVaultManagerShouldSaveData(_: SecureVaultManager) -> Bool {
        return true
    }

    public func secureVaultManager(_: SecureVaultManager,
                                   promptUserToStoreAutofillData data: AutofillData,
                                   withTrigger trigger: AutofillUserScript.GetTriggerType?) {
        // No-op, the content overlay view controller should not be prompting the user to store data
    }

    public func secureVaultManager(_: SecureVaultManager,
                                   promptUserToAutofillCredentialsForDomain domain: String,
                                   withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                                   withTrigger trigger: AutofillUserScript.GetTriggerType,
                                   onAccountSelected account: @escaping (SecureVaultModels.WebsiteAccount?) -> Void,
                                   completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {
        // no-op on macOS
    }

    public func secureVaultManager(_: SecureVaultManager, promptUserToAutofillCreditCardWith creditCards: [SecureVaultModels.CreditCard], withTrigger trigger: AutofillUserScript.GetTriggerType, completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        // no-op on macOS
    }

    public func secureVaultManager(_: SecureVaultManager, didFocusFieldFor mainType: AutofillUserScript.GetAutofillDataMainType, withCreditCards creditCards: [SecureVaultModels.CreditCard], completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        // no-op on macOS
    }

    public func secureVaultManager(_: SecureVaultManager,
                                   promptUserWithGeneratedPassword password: String,
                                   completionHandler: @escaping (Bool) -> Void) {
        // no-op on macOS
    }

    public func secureVaultManager(_: SecureVaultManager,
                                   promptUserToImportCredentialsForDomain domain: String,
                                   completionHandler: @escaping (Bool) -> Void) {
        // no-op on macOS
    }

    public func secureVaultManager(_: SecureVaultManager,
                                   isAuthenticatedFor type: AutofillType,
                                   completionHandler: @escaping (Bool) -> Void) {

        switch type {

        // Require bio authentication for filling sensitive data via DDG password manager
        case .card, .password:
            let autofillPrefs = AutofillPreferences()
            if DeviceAuthenticator.shared.requiresAuthentication &&
                autofillPrefs.autolockLocksFormFilling &&
                autofillPrefs.passwordManager == .duckduckgo {
                DeviceAuthenticator.shared.authenticateUser(reason: .autofill) { result in
                    if case .success = result {
                        completionHandler(true)
                    } else {
                        completionHandler(false)
                    }
                }
            } else {
                completionHandler(true)
            }

        default:
            completionHandler(true)
        }

    }

    public func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: String) {
        let parameters = usageProvider.formattedFillDate.flatMap { [AutofillPixelKitEvent.Parameter.lastUsed: $0] } ?? [:]
        PixelKit.fire(GeneralPixel.formAutofilled(kind: type.formAutofillKind), withAdditionalParameters: parameters)
        NotificationCenter.default.post(name: .autofillFillEvent, object: nil)

        if type.formAutofillKind == .password &&
            passwordManagerCoordinator.isEnabled {
            passwordManagerCoordinator.reportPasswordAutofill()
        }
    }

    public func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler handler: @escaping (Bool) -> Void) {
        DeviceAuthenticator.shared.authenticateUser(reason: .autofillCreditCards) { authenticationResult in
            handler(authenticationResult.authenticated)
        }
    }

    public func secureVaultError(_ error: SecureStorageError) {
        SecureVaultReporter.shared.secureVaultError(error)
    }

    public func secureVaultKeyStoreEvent(_ event: SecureStorageKeyStoreEvent) {
        SecureVaultReporter.shared.secureVaultKeyStoreEvent(event)
    }

    public func secureVaultManager(_: BrowserServicesKit.SecureVaultManager, didReceivePixel pixel: AutofillUserScript.JSPixel) {
        if pixel.isEmailPixel {
            let emailParameters = self.emailManager.emailPixelParameters
            let additionalPixelParameters = pixel.pixelParameters ?? [:]
            let pixelParameters = emailParameters.merging(additionalPixelParameters) { (first, _) in first }

            self.emailManager.updateLastUseDate()

            PixelKit.fire(NonStandardEvent(GeneralPixel.jsPixel(pixel)), withAdditionalParameters: pixelParameters)
            NotificationCenter.default.post(name: .autofillFillEvent, object: nil)
        } else if pixel.isCredentialsImportPromotionPixel {
            PixelKit.fire(NonStandardEvent(GeneralPixel.jsPixel(pixel)))
        } else {
            var existingParameters = pixel.pixelParameters ?? [:]
            var parameters = usageProvider.formattedFillDate.flatMap {
                existingParameters[AutofillPixelKitEvent.Parameter.lastUsed] = $0
                return existingParameters
            } ?? existingParameters
            PixelKit.fire(GeneralPixel.jsPixel(pixel), withAdditionalParameters: parameters)
            if pixel.isIdentityPixel {
                NotificationCenter.default.post(name: .autofillFillEvent, object: nil)
            }
        }
    }

    public func secureVaultManager(_: SecureVaultManager, didRequestCreditCardsManagerForDomain domain: String) {
        autofillPreferencesModel.showAutofillPopover(.cards, source: .manage)
    }

    public func secureVaultManager(_: SecureVaultManager, didRequestIdentitiesManagerForDomain domain: String) {
        autofillPreferencesModel.showAutofillPopover(.identities, source: .manage)
    }

    public func secureVaultManager(_: SecureVaultManager, didRequestPasswordManagerForDomain domain: String) {
        let mngr = PasswordManagerCoordinator.shared
        if mngr.isEnabled {
            mngr.bitwardenManagement.openBitwarden()
        } else {
            autofillPreferencesModel.showAutofillPopover(.logins, source: .manage)
        }
    }

    public func secureVaultManager(_: SecureVaultManager, didRequestRuntimeConfigurationForDomain domain: String, completionHandler: @escaping (String?) -> Void) {
        let isGPCEnabled = WebTrackingProtectionPreferences.shared.isGPCEnabled
        let properties = ContentScopeProperties(gpcEnabled: isGPCEnabled,
                                                sessionKey: topAutofillUserScript?.sessionKey ?? "",
                                                messageSecret: topAutofillUserScript?.messageSecret ?? "",
                                                featureToggles: ContentScopeFeatureToggles.supportedFeaturesOnMacOS(privacyConfigurationManager.privacyConfig))

        do {
            let runtimeConfiguration = try DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfigurationManager,
                                                                                 properties: properties)
                .build()
                .buildRuntimeConfigResponse()

            completionHandler(runtimeConfiguration)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to load JS for DefaultAutofillSourceProvider: \(error.localizedDescription)")
        }
    }
}

extension ContentOverlayViewController: AutofillCredentialsImportPresentationDelegate {
    public func autofillDidRequestCredentialsImportFlow(onFinished: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        let viewModel = DataImportViewModel(onFinished: onFinished, onCancelled: onCancelled)
        DataImportFlowLauncher().launchDataImport(model: viewModel, isDataTypePickerExpanded: true)
    }
}
