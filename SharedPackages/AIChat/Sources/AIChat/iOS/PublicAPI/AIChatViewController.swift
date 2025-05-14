//
//  AIChatViewController.swift
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

#if os(iOS)
import UIKit
import Combine
import WebKit
import SwiftUI

/// A protocol that defines the delegate methods for `AIChatViewController`.
public protocol AIChatViewControllerDelegate: AnyObject {
    /// Tells the delegate that a request to load a URL has been made.
    ///
    /// - Parameters:
    ///   - viewController: The `AIChatViewController` instance making the request.
    ///   - url: The `URL` that is requested to be loaded.
    func aiChatViewController(_ viewController: AIChatViewController, didRequestToLoad url: URL)

    /// Tells the delegate that the `AIChatViewController` has finished its task.
    ///
    /// - Parameter viewController: The `AIChatViewController` instance that has finished.
    func aiChatViewControllerDidFinish(_ viewController: AIChatViewController)

    /// Tells the delegate that the `AIChatViewController` has finished downloading a file.
    ///
    /// - Parameters:
    ///   - viewController: The `AIChatViewController` instance that completed the download.
    ///   - fileName: The name of the downloaded file that the user has requested to open
    func aiChatViewController(_ viewController: AIChatViewController, didRequestOpenDownloadWithFileName fileName: String)
}

public final class AIChatViewController: UIViewController {
    public weak var delegate: AIChatViewControllerDelegate?
    private let chatModel: AIChatViewModeling
    private var webViewController: AIChatWebViewController?
    private let chatInputHostingController: UIHostingController<AnyView>?
    private var chatInputHeightConstraint: NSLayoutConstraint?
    private var chatInputBottomConstraint: NSLayoutConstraint?

    public var webView: WKWebView? {
        webViewController?.webView
    }

    private lazy var titleBarView: TitleBarView = {
        let title = UserText.aiChatTitle

        let titleBarView = TitleBarView(title: UserText.aiChatTitle) { [weak self] in
            guard let self = self else { return }
            self.delegate?.aiChatViewControllerDidFinish(self)
        }
        return titleBarView
    }()

    /// Initializes a new instance of `AIChatViewController` with the specified remote settings and web view configuration.
    ///
    /// - Parameters:
    ///   - remoteSettings: An object conforming to `AIChatSettingsProvider` that provides remote settings.
    ///   - webViewConfiguration: A `WKWebViewConfiguration` object used to configure the web view.
    ///   - requestAuthHandler: A `AIChatRequestAuthorizationHandling` object to handle decide policy callbacks
    ///   - inspectableWebView: Boolean indicating if the webView should be inspectable
    ///   - downloadsPath: URL indicating the path where downloads should be saved
    ///   - chatInputBox: A SwiftUI view to be used as the native input box for duck.ai
    public convenience init(settings: AIChatSettingsProvider,
                            webViewConfiguration: WKWebViewConfiguration,
                            requestAuthHandler: AIChatRequestAuthorizationHandling,
                            inspectableWebView: Bool,
                            downloadsPath: URL,
                            userAgentManager: AIChatUserAgentProviding,
                            chatInputBox: AnyView?) {
        let chatModel = AIChatViewModel(webViewConfiguration: webViewConfiguration,
                                        settings: settings,
                                        requestAuthHandler: requestAuthHandler,
                                        inspectableWebView: inspectableWebView,
                                        downloadsPath: downloadsPath,
                                        userAgentManager: userAgentManager)
        self.init(chatModel: chatModel, chatInputBox: chatInputBox)
    }

    internal init(chatModel: AIChatViewModeling, chatInputBox: AnyView?) {
        self.chatModel = chatModel
        if let view = chatInputBox {
            self.chatInputHostingController = UIHostingController(rootView: view)
        } else {
            self.chatInputHostingController = nil
        }

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Lifecycle
extension AIChatViewController {

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        setupTitleBar()
        addWebViewController()
        setupChatInputBox()
    }
}

// MARK: - Public functions
extension AIChatViewController {
    public func loadQuery(_ query: String, autoSend: Bool) {
        // Ensure the webViewController is added before loading the query
        if webViewController == nil {
            addWebViewController()
        }
        webViewController?.loadQuery(query, autoSend: autoSend)
    }

    public func reload() {
        webViewController?.reload()
    }
}

// MARK: - Keyboard manager
extension AIChatViewController {
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIResponder.keyboardWillShowNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIResponder.keyboardWillHideNotification,
                                                  object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let durationNumber = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else {
            return
        }
        let duration = durationNumber.doubleValue
        let keyboardFrame = frameValue.cgRectValue
        let kbFrameInView = view.convert(keyboardFrame, from: nil)
        chatInputBottomConstraint?.constant = -kbFrameInView.height
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let durationNumber = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else {
            return
        }
        let duration = durationNumber.doubleValue
        chatInputBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - Views Setup
extension AIChatViewController {

    private func setupChatInputBox() {
        guard let chatInputHostingController = chatInputHostingController else { return }

        addChild(chatInputHostingController)
        chatInputHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        chatInputHostingController.view.backgroundColor = .clear
        view.addSubview(chatInputHostingController.view)

        let bottomConstraint = chatInputHostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        chatInputBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            chatInputHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatInputHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint
        ])
        chatInputHostingController.didMove(toParent: self)
    }

    private func setupTitleBar() {
        view.addSubview(titleBarView)
        titleBarView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            titleBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBarView.heightAnchor.constraint(equalToConstant: 68)
        ])
    }

    private func addWebViewController() {
        guard webViewController == nil else { return }

        let downloadsHandler = DownloadHandler(downloadsPath: chatModel.downloadsPath)
        let viewController = AIChatWebViewController(chatModel: chatModel,
                                                     downloadHandler: downloadsHandler)
        viewController.delegate = self
        webViewController = viewController

        addChild(viewController)
        view.addSubview(viewController.view)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: titleBarView.bottomAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        viewController.didMove(toParent: self)

        if let chatInputView = chatInputHostingController?.view {
            view.bringSubviewToFront(chatInputView)
        }
    }

    private func removeWebViewController() {
        if viewIfLoaded?.window == nil {
            webViewController?.removeFromParent()
            webViewController?.view.removeFromSuperview()
            webViewController = nil
        }
    }
}

extension AIChatViewController: AIChatWebViewControllerDelegate {
    func aiChatWebViewController(_ viewController: AIChatWebViewController, didRequestOpenDownloadWithFileName fileName: String) {
        delegate?.aiChatViewController(self, didRequestOpenDownloadWithFileName: fileName)
    }

    func aiChatWebViewController(_ viewController: AIChatWebViewController, didRequestToLoad url: URL) {
        delegate?.aiChatViewController(self, didRequestToLoad: url)
    }
}
#endif
