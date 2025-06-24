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
import BrowserServicesKit
import PixelKit
import WebKit
import Combine
import DataBrokerProtectionCore

final public class DataBrokerProtectionViewController: UIViewController {

    private let webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable
    private let webUIViewModel: DBPUIViewModel

    private var activityIndicatorView: UIActivityIndicatorView?

    private let openURLHandler: (URL) -> Void
    private var reloadObserver: NSObjectProtocol?

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

    public init(dbpUIViewModelDelegate: DBPUIViewModelDelegate,
                privacyConfigManager: PrivacyConfigurationManaging,
                contentScopeProperties: ContentScopeProperties,
                webUISettings: DataBrokerProtectionWebUIURLSettingsRepresentable,
                openURLHandler: @escaping (URL) -> Void) {
        self.openURLHandler = openURLHandler
        self.webUISettings = webUISettings

        guard let pixelKit = PixelKit.shared else {
            fatalError("PixelKit not set up")
        }
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS)

        self.webUIViewModel = DBPUIViewModel(delegate: dbpUIViewModelDelegate,
                                             webUISettings: webUISettings,
                                             pixelHandler: sharedPixelsHandler,
                                             privacyConfigManager: privacyConfigManager,
                                             contentScopeProperties: contentScopeProperties)

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        setupWebView()
        setupLoadingView()

        if let url = URL(string: webUISettings.selectedURL) {
            webView.load(url)
        } else {
            loadingView.stopAnimating()
            assertionFailure("Selected URL is not valid \(webUISettings.selectedURL)")
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
    }

    private func setupLoadingView() {
        view.addSubview(loadingView)

        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadingView.startAnimating()
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

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingView.startAnimating()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingView.stopAnimating()
    }
}

public protocol DataBrokerProtectionViewControllerProvider {
    func dataBrokerProtectionViewController() -> DataBrokerProtectionViewController
}

public struct DataBrokerProtectionViewControllerRepresentation: UIViewControllerRepresentable {

    private let dbpViewControllerProvider: DataBrokerProtectionViewControllerProvider

    public init(dbpViewControllerProvider: DataBrokerProtectionViewControllerProvider) {
        self.dbpViewControllerProvider = dbpViewControllerProvider
    }

    public func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {

    }

    public func makeUIViewController(context: Context) -> some UIViewController {

        return dbpViewControllerProvider.dataBrokerProtectionViewController()
    }
}
