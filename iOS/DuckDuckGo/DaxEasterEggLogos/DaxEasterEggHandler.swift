//
//  DaxEasterEggHandler.swift
//  DuckDuckGo
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

import Foundation
import WebKit

/// Delegate protocol for receiving extracted DuckDuckGo logo URLs.
///
/// Implemented by components that need to display or process dynamic logos
/// extracted from DuckDuckGo search pages (typically MainViewController).
protocol DaxEasterEggDelegate: AnyObject {
    /// Called when a dynamic logo URL has been extracted and processed.
    ///
    /// - Parameters:
    ///   - handler: The handler that extracted the logo
    ///   - logoURL: The processed absolute URL of the logo, or nil if no logo found
    ///   - pageURL: The URL of the page where the logo was extracted from
    func daxEasterEggHandler(_ handler: DaxEasterEggHandling, didFindLogoURL logoURL: String?, for pageURL: String)
}

/// Protocol defining the interface for extracting and processing DuckDuckGo dynamic logos.
///
/// This protocol enables testability by allowing mock implementations during testing.
/// The handler coordinates between JavaScript extraction and native processing.
protocol DaxEasterEggHandling: AnyObject {
    /// Delegate that receives processed logo URLs
    var delegate: DaxEasterEggDelegate? { get set }
    
    /// Triggers logo extraction by executing JavaScript directly on the web view.
    /// Should only be called on DuckDuckGo search pages.
    func extractLogosForCurrentPage()
}

/// Handler that manages extraction and processing of dynamic logos from DuckDuckGo search pages.
///
/// This class executes JavaScript directly to find logos and processes the results for the native UI.
/// It processes raw logo URLs by converting relative paths to absolute URLs and handling 
/// DuckDuckGo's "themed|" URL format.
///
/// The handler is created on-demand when navigating to DuckDuckGo search pages.
class DaxEasterEggHandler: DaxEasterEggHandling {
    
    public weak var delegate: DaxEasterEggDelegate?
    private weak var webView: WKWebView?
    private let logoCache: DaxEasterEggLogoCaching
    
    init(webView: WKWebView, logoCache: DaxEasterEggLogoCaching = DaxEasterEggLogoCache()) {
        self.webView = webView
        self.logoCache = logoCache
    }
    
    func extractLogosForCurrentPage() {
        guard let webView = webView else {
            Logger.daxEasterEgg.debug("extractLogosForCurrentPage - webView is nil")
            return
        }
        
        Logger.daxEasterEgg.debug("extractLogosForCurrentPage - executing JavaScript directly on URL: \(webView.url?.absoluteString ?? "no-url")")
        
        Task { [weak self, weak webView] in
            guard let self = self, let webView = webView else { return }
            await self.executeLogoExtraction(webView: webView)
        }
    }
    
    private func executeLogoExtraction(webView: WKWebView) async {
        let extractionJS = """
        (function() {
            try {
                function findLogo() {
                    var ddgLogo = document.querySelector('.js-logo-ddg');
                    
                    if (!ddgLogo) {
                        ddgLogo = document.querySelector('.logo-dynamic');
                    }
                    if (!ddgLogo) {
                        ddgLogo = document.querySelector('[data-dynamic-logo]');
                    }
                    
                    if (!ddgLogo) {
                        return null;
                    }
                    
                    if (ddgLogo.dataset && ddgLogo.dataset.dynamicLogo) {
                        return 'themed|' + ddgLogo.dataset.dynamicLogo;
                    }
                    
                    return null;
                }
                
                return findLogo();
            } catch (error) {
                console.error('DaxEasterEgg: Error in logo extraction:', error);
                return null;
            }
        })();
        """
        
        do {
            let logoURL: String? = try await webView.evaluateJavaScript(extractionJS)
            Logger.daxEasterEgg.debug("executeLogoExtraction - extracted logo: \(logoURL ?? "nil")")
            await didExtractLogo(logoURL, from: webView.url?.absoluteString ?? "")
        } catch {
            Logger.daxEasterEgg.error("executeLogoExtraction - JavaScript error: \(error)")
            await didExtractLogo(nil, from: webView.url?.absoluteString ?? "")
        }
    }
    
    private func didExtractLogo(_ logoURL: String?, from pageURL: String) async {
        Logger.daxEasterEgg.debug("didExtractLogo - Raw: \(logoURL ?? "nil"), Page: \(pageURL)")
        
        // Process the logo URL (convert relative to absolute, handle "themed|" prefix)
        let processedURL = processLogoURL(logoURL)
        
        Logger.daxEasterEgg.debug("didExtractLogo - Processed: \(processedURL ?? "nil")")
        
        // Store successful extractions in cache for future use
        if let processedURL = processedURL,
           let url = URL(string: pageURL),
           let searchQuery = url.searchQuery {
            logoCache.storeLogo(processedURL, for: searchQuery)
        }
        
        await MainActor.run {
            delegate?.daxEasterEggHandler(self, didFindLogoURL: processedURL, for: pageURL)
        }
    }
    
    private func processLogoURL(_ rawURL: String?) -> String? {
        guard let rawURL = rawURL else { return nil }
        
        // Decode URL-encoded string
        guard let decodedURL = rawURL.removingPercentEncoding else {
            return nil
        }
        
        // Parse the format: "themed|/path"
        let components = decodedURL.split(separator: "|", maxSplits: 1)
        guard components.count == 2 else {
            return nil
        }
        
        let path = String(components[1])
        
        // Convert relative path to absolute URL
        if path.hasPrefix("/") {
            return "https://duckduckgo.com" + path
        } else if path.hasPrefix("http") {
            return path
        }
        
        return nil
    }
}
