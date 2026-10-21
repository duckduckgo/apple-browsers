//
//  ReaderModeViewController.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import ReaderMode
import UIKit
import WebKit

@MainActor
final class ReaderModeViewController: UIViewController, WKNavigationDelegate {
    private let article: ReaderArticle
    private let contentRuleLists: [WKContentRuleList]
    private let close: () -> Void
    private let openLink: (URL) -> Void
    private var initialNavigation: WKNavigation?
    private(set) var readerWebView: WKWebView!

    init(article: ReaderArticle, contentRuleLists: [WKContentRuleList],
         close: @escaping () -> Void, openLink: @escaping (URL) -> Void) {
        self.article = article
        self.contentRuleLists = contentRuleLists
        self.close = close
        self.openLink = openLink
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = UIColor(designSystemColor: .background)
        view.backgroundColor = background
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        contentRuleLists.forEach(configuration.userContentController.add)
        readerWebView = WKWebView(frame: .zero, configuration: configuration)
        readerWebView.clipsToBounds = true
        // Transparent until the page paints, so the matching native background shows instead of a white flash.
        readerWebView.isOpaque = false
        readerWebView.backgroundColor = background
        readerWebView.scrollView.backgroundColor = background
        readerWebView.navigationDelegate = self
        readerWebView.allowsLinkPreview = false
        readerWebView.accessibilityIdentifier = "readerModeContent"
        readerWebView.translatesAutoresizingMaskIntoConstraints = false
        let closeButton = UIButton(type: .system)
        closeButton.setImage(DesignSystemImages.Glyphs.Size24.close, for: .normal)
        closeButton.tintColor = UIColor(designSystemColor: .textPrimary)
        closeButton.accessibilityLabel = UserText.readerModeClose
        closeButton.accessibilityIdentifier = "readerModeClose"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        view.addSubview(readerWebView)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -6),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            readerWebView.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            readerWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            readerWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            readerWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // The article URL as base lets content blocking rules that depend on the top-level site match the original page.
        initialNavigation = readerWebView.loadHTMLString(article.renderedHTML, baseURL: article.sourceURL)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if initialNavigation != nil, navigationAction.navigationType == .other, navigationAction.targetFrame?.isMainFrame == true {
            initialNavigation = nil
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            openLink(url)
        }
    }
}

extension ReaderTheme {
    /// Reader page colors resolved from the design system for light and dark appearance.
    static var designSystem: ReaderTheme {
        ReaderTheme(background: colorPair(.background),
                    text: colorPair(.textPrimary),
                    secondaryText: colorPair(.textSecondary),
                    link: colorPair(.accentTextPrimary),
                    codeBackground: colorPair(.surface),
                    border: colorPair(.lines))
    }

    private static func colorPair(_ designSystemColor: DesignSystemColor) -> ColorPair {
        let color = UIColor(designSystemColor: designSystemColor)
        return ColorPair(light: readerColor(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))),
                         dark: readerColor(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))))
    }

    private static func readerColor(_ color: UIColor) -> ReaderTheme.Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ReaderTheme.Color(red: red, green: green, blue: blue, alpha: alpha)
    }
}
