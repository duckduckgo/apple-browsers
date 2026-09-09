//
//  DataBrokerProtectionViewController.swift
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

import UIKit
import SwiftUI
import Common
import FoundationExtensions
import BrowserServicesKit
import PixelKit
import WebKit
import Combine
import DataBrokerProtectionCore
import os.log
import PrivacyConfig
import Subscription

final public class DataBrokerProtectionViewController: UIViewController {

    private let webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable
    private var authenticationDelegate: DBPIOSInterface.AuthenticationDelegate
    private var databaseDelegate: DBPIOSInterface.DatabaseDelegate
    private var userEventsDelegate: DBPIOSInterface.UserEventsDelegate
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let contentScopeProperties: ContentScopeProperties

    private var activityIndicatorView: UIActivityIndicatorView?

    private let feedbackViewCreator: () -> (any View)
    private let openURLHandler: (URL) -> Void
    private var reloadObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private let isWebViewInspectable: Bool
    private var isViewVisible = false
    private var hasLoadedDashboard = false

    private lazy var sharedPixelsHandler: DataBrokerProtectionSharedPixelsHandler = {
        guard let pixelKit = PixelKit.shared else {
            fatalError("PixelKit not set up")
        }
        return DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS)
    }()

    private lazy var interactionPixels = DataBrokerProtectionInteractionPixels(
        handler: sharedPixelsHandler,
        repository: DataBrokerProtectionInteractionPixelsUserDefaults(userDefaults: .dbp)
    )

    private lazy var webUIViewModel: DBPUIViewModel = {
        return DBPUIViewModel(authenticationDelegate: authenticationDelegate,
                              databaseDelegate: databaseDelegate,
                              feedbackFormDelegate: self,
                              userEventsDelegate: userEventsDelegate,
                              webUISettings: webUISettings,
                              pixelHandler: sharedPixelsHandler,
                              privacyConfigManager: privacyConfigManager,
                              contentScopeProperties: contentScopeProperties)
    }()

    private lazy var webView: WKWebView = {
        let configuration = webUIViewModel.setupCommunicationLayer()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.uiDelegate = self
        webView.navigationDelegate = self
        return webView
    }()

    private lazy var loadingView: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .label
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        return activityIndicator
    }()

    public init(authenticationDelegate: DBPIOSInterface.AuthenticationDelegate,
                databaseDelegate: DBPIOSInterface.DatabaseDelegate,
                userEventsDelegate: DBPIOSInterface.UserEventsDelegate,
                privacyConfigManager: PrivacyConfigurationManaging,
                contentScopeProperties: ContentScopeProperties,
                webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable,
                openURLHandler: @escaping (URL) -> Void,
                feedbackViewCreator: @escaping () -> (any View),
                isWebViewInspectable: Bool = false) {
        self.openURLHandler = openURLHandler
        self.feedbackViewCreator = feedbackViewCreator
        self.webUISettings = webUISettings

        self.authenticationDelegate = authenticationDelegate
        self.databaseDelegate = databaseDelegate
        self.userEventsDelegate = userEventsDelegate
        self.privacyConfigManager = privacyConfigManager
        self.contentScopeProperties = contentScopeProperties
        self.isWebViewInspectable = isWebViewInspectable

        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        if let reloadObserver {
            NotificationCenter.default.removeObserver(reloadObserver)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        setupLoadingView()
        subscribeToSubscriptionChangeNotifications()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await databaseDelegate.prepareDatabaseAccess()
                webUIViewModel.updatePartialProfile()
                loadDashboard()
            } catch {
                Logger.dataBrokerProtection.error("Failed to wait for dashboard database access: \(error.localizedDescription, privacy: .public)")
                loadingView.stopAnimating()
            }
        }
    }

    private func setupWebView() {
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        if #available(iOS 16.4, *) {
            webView.isInspectable = isWebViewInspectable
        }

        view.bringSubviewToFront(loadingView)
    }

    private func setupLoadingView() {
        view.addSubview(loadingView)

        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadingView.startAnimating()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewVisible = true

        guard hasLoadedDashboard else { return }
        dashboardDidBecomeVisible()
    }

    override public func viewDidDisappear(_ animated: Bool) {
        isViewVisible = false
        cancellables.removeAll()
        if hasLoadedDashboard {
            webUIViewModel.viewDidDisappear()
        }
        super.viewDidDisappear(animated)
    }

    private func loadDashboard() {
        setupWebView()
        hasLoadedDashboard = true

        if let url = URL(string: webUISettings.selectedURL) {
            webView.load(url)
        } else {
            loadingView.stopAnimating()
            assertionFailure("Selected URL is not valid \(webUISettings.selectedURL)")
        }

        if isViewVisible {
            dashboardDidBecomeVisible()
        }
    }

    private func dashboardDidBecomeVisible() {
        webUIViewModel.viewDidAppear()
        subscribeToBackgroundRefreshNotifications()
        Task { [weak self] in
            guard let self else { return }
            let isAuthenticated = await self.authenticationDelegate.isUserAuthenticated()
            self.interactionPixels.fireInteractionPixel(isAuthenticated: isAuthenticated)
            self.sharedPixelsHandler.fire(.dashboardOpen(isAuthenticated: isAuthenticated, isFreeScan: !isAuthenticated))
        }
    }

    private func subscribeToBackgroundRefreshNotifications() {
        cancellables.removeAll()

        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification),
            NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange),
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        )
        .sink { [weak self] notification in
            Logger.dataBrokerProtection.debug("Background refresh state may have changed: \(notification.name.rawValue)")
            self?.notifyBackgroundAppRefreshChange()
        }
        .store(in: &cancellables)
    }

    private func subscribeToSubscriptionChangeNotifications() {
        reloadObserver = NotificationCenter.default.addObserver(forName: .subscriptionDidChange,
                                                                object: nil,
                                                                queue: .main) { [weak self] _ in
            // Refresh the web UI under the subscription flow so PIR handshakes with the new auth state.
            self?.webView.reload()
        }
    }

    private func notifyBackgroundAppRefreshChange() {
        Task { @MainActor in
            await webUIViewModel.sendBackgroundAppRefreshDidChange(into: webView)
        }
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        guard let selectedURL = URL(string: webUISettings.selectedURL),
              let selectedHost = selectedURL.host,
              url.host?.caseInsensitiveCompare(selectedHost) == .orderedSame else {
            return false
        }

        return SubscriptionPurchaseFlowPath.contains(url.path)
    }
}

extension DataBrokerProtectionViewController: DBPUIViewModelOpenFeedbackFormDelegate {
    public func openSendFeedbackForm() {
        DispatchQueue.main.async {
            let view = self.feedbackViewCreator()
            let hostingController = UIHostingController(rootView: AnyView(view))
            self.navigationController?.pushViewController(hostingController, animated: true)
        }
    }
}

extension DataBrokerProtectionViewController: WKUIDelegate {
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        openURLHandler(url)
        return nil
    }
}

extension DataBrokerProtectionViewController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        loadingView.stopAnimating()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        loadingView.stopAnimating()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode else {
            // if there's no http status code to act on, exit and allow navigation
            return .allow
        }

        if statusCode >= 400 {
            return .cancel
        }

        return .allow
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame == true,
              let url = navigationAction.request.url,
              shouldOpenExternally(url) else {
            return .allow
        }

        openURLHandler(url)
        return .cancel
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingView.startAnimating()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingView.stopAnimating()
    }
}

public struct DataBrokerProtectionViewControllerRepresentation: UIViewControllerRepresentable {

    private let dbpViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider

    public init(dbpViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider) {
        self.dbpViewControllerProvider = dbpViewControllerProvider
    }

    public func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {

    }

    public func makeUIViewController(context: Context) -> some UIViewController {

        return dbpViewControllerProvider.dataBrokerProtectionViewController()
    }
}
