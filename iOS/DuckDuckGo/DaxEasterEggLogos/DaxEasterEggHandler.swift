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
public protocol DaxEasterEggDelegate: AnyObject {
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
public protocol DaxEasterEggHandling: AnyObject {
    /// Delegate that receives processed logo URLs
    var delegate: DaxEasterEggDelegate? { get set }
    
    /// Triggers logo extraction by calling the UserScript's JavaScript function.
    /// Should only be called on DuckDuckGo search pages.
    func extractLogosForCurrentPage()
    
    /// Processes a raw logo URL extracted by JavaScript.
    /// Converts relative paths to absolute URLs and handles the "themed|" prefix format.
    ///
    /// - Parameters:
    ///   - logoURL: Raw logo URL from JavaScript (format: "themed|/path")
    ///   - pageURL: URL of the page where logo was extracted
    func didExtractLogo(_ logoURL: String?, from pageURL: String)
    
}

/// Handler that manages extraction and processing of dynamic logos from DuckDuckGo search pages.
///
/// This class coordinates between the DaxEasterEggUserScript (which runs JavaScript to find logos)
/// and the native UI (which displays the logos). It processes raw logo URLs by converting
/// relative paths to absolute URLs and handling DuckDuckGo's "themed|" URL format.
///
/// The handler follows the same pattern as FindInPage: it's created on-demand and connected
/// to the UserScript via a property in TabViewController.
public class DaxEasterEggHandler: DaxEasterEggHandling {
    
    public weak var delegate: DaxEasterEggDelegate?
    private weak var webView: WKWebView?
    
    public init(webView: WKWebView) {
        self.webView = webView
    }
    
    public func extractLogosForCurrentPage() {
        guard let webView = webView else {
            return
        }
        
        // Call the global function provided by UserScript
        webView.evaluateJavaScript("window.extractDaxEasterEggLogo()")
    }
    
    public func didExtractLogo(_ logoURL: String?, from pageURL: String) {
        // Process the logo URL (convert relative to absolute, handle "themed|" prefix)
        let processedURL = processLogoURL(logoURL)
        
        delegate?.daxEasterEggHandler(self, didFindLogoURL: processedURL, for: pageURL)
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
