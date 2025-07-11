//
//  AIChatWebViewController.swift
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

#if os(iOS)
import UIKit
import WebKit

protocol AIChatWebViewControllerDelegate: AnyObject {
    @MainActor func aiChatWebViewController(_ viewController: AIChatWebViewController, didRequestToLoad url: URL)
    @MainActor func aiChatWebViewController(_ viewController: AIChatWebViewController, didRequestOpenDownloadWithFileName fileName: String)
}

final class AIChatWebViewController: UIViewController {
    weak var delegate: AIChatWebViewControllerDelegate?
    private let chatModel: AIChatViewModeling
    private var downloadHandler: DownloadHandling

    private(set) lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero, configuration: chatModel.webViewConfiguration)
        webView.isOpaque = false /// Required to make the background color visible
        webView.backgroundColor = .webViewBackgroundColor
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    private lazy var loadingView: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .label
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        return activityIndicator
    }()

    init(chatModel: AIChatViewModeling, downloadHandler: DownloadHandling) {
        self.chatModel = chatModel
        self.downloadHandler = downloadHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        setupWebView()
        setupLoadingView()
        loadWebsite()
        setupDownloadHandler()
    }

    private func setupDownloadHandler() {
        downloadHandler.onDownloadComplete = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let filename):
                self.view.showDownloadCompletionToast(for: filename) {
                    self.delegate?.aiChatWebViewController(self, didRequestOpenDownloadWithFileName: filename)
                }

            case .failure:
                self.view.showDownloadFailedToast()
            }
        }
    }

    private func setupWebView() {
        view.addSubview(webView)
        webView.customUserAgent = chatModel.userAgent

        if #available(iOS 16.4, *) {
            webView.isInspectable = chatModel.inspectableWebView
        }

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
    }
}

// MARK: - WebView functions

extension AIChatWebViewController {

    struct QueryParameters {
        static let queryKey = "q"
        static let autoSendKey = "prompt"
        static let autoSendValue = "1"
        static let toolChoice = "toolChoice"
    }

    func reload() {
        loadWebsite()
    }

    private func loadWebsite() {
        let request = URLRequest(url: chatModel.aiChatURL)
        webView.load(request)
    }

    func loadQuery(_ query: String, autoSend: Bool, tools: [AIChatRAGTool]?) {
        let url = buildQueryURL(query: query, autoSend: autoSend, tools: tools)
        webView.load(URLRequest(url: url))
    }

    private func buildQueryURL(query: String, autoSend: Bool, tools: [AIChatRAGTool]?) -> URL {
        guard var components = URLComponents(url: chatModel.aiChatURL, resolvingAgainstBaseURL: false) else {
            return chatModel.aiChatURL
        }

        var queryItems = components.queryItems ?? []

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.removeAll { $0.name == QueryParameters.queryKey }
            queryItems.append(URLQueryItem(name: QueryParameters.queryKey, value: query))
        }

        if autoSend {
            queryItems.removeAll { $0.name == QueryParameters.autoSendKey }
            queryItems.append(URLQueryItem(name: QueryParameters.autoSendKey, value: QueryParameters.autoSendValue))
        }

        if let tools = tools, !tools.isEmpty {
            queryItems.removeAll { $0.name == QueryParameters.toolChoice }
            for tool in tools {
                queryItems.append(URLQueryItem(name: QueryParameters.toolChoice, value: tool.rawValue))
            }
        }

        components.queryItems = queryItems
        return components.url ?? chatModel.aiChatURL
    }
}

// MARK: - WKNavigationDelegate

extension AIChatWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .allow
        }

        if shouldAllowNavigation(for: url, with: navigationAction) {
            return .allow
        } else {
            delegate?.aiChatWebViewController(self, didRequestToLoad: url)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let url = navigationResponse.response.url else {
            return .allow
        }
        return url.scheme == SchemeType.blob ? .download : .allow
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloadHandler
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateLoadingState(isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateLoadingState(isLoading: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateLoadingState(isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateLoadingState(isLoading: false)
    }

    private func shouldAllowNavigation(for url: URL, with navigationAction: WKNavigationAction) -> Bool {
        return url.scheme == SchemeType.blob || chatModel.shouldAllowRequestWithNavigationAction(navigationAction)
    }

    private func updateLoadingState(isLoading: Bool) {
        if isLoading {
            loadingView.startAnimating()
        } else {
            loadingView.stopAnimating()
        }
    }
}

enum SchemeType {
    static let blob = "blob"
}
#endif
