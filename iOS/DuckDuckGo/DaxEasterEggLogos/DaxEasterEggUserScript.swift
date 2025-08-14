//
//  DaxEasterEggUserScript.swift
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

import Core
import WebKit
import UserScript

/// UserScript that extracts dynamic logos from DuckDuckGo search pages.
///
/// This UserScript provides JavaScript functionality to detect and extract themed logos 
/// (like Terminator, Predator themes) from DuckDuckGo search result pages. The extraction
/// is triggered manually by native code only on DuckDuckGo search pages.
///
/// The JavaScript defines a global `window.extractDaxEasterEggLogo()` function that:
/// - Searches for logo elements with `data-dynamic-logo` attributes
/// - Extracts the logo URL and formats it as "themed|/path"  
/// - Sends the result to native code via webkit message handlers
///
/// Requires `requiresRunInPageContentWorld = true` to ensure the global function
/// is accessible from native `webView.evaluateJavaScript()` calls.
public class DaxEasterEggUserScript: NSObject, UserScript {

    public var source: String = """
(function() {
    console.log('DaxEasterEgg: UserScript loaded');
    
    // Expose global function for manual triggering by native code
    window.extractDaxEasterEggLogo = function() {
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
        
        var logoURL = findLogo();
        
        // Always send message to native, even when no logo is found
        // This allows the UI to reset to default icon when needed
        webkit.messageHandlers.daxEasterEggHandler.postMessage({
            logoURL: logoURL, // will be null if no logo found
            url: window.location.href
        });
    };
    
    console.log('DaxEasterEgg: Function defined, typeof:', typeof window.extractDaxEasterEggLogo);
    
})();
"""

    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    
    public var forMainFrameOnly: Bool = true
    
    public var messageNames: [String] = ["daxEasterEggHandler"]
    
    public var requiresRunInPageContentWorld: Bool = true
    
    /// Handler that processes extracted logo URLs and manages business logic.
    /// Set by TabViewController when the handler is created.
    var daxEasterEggHandler: DaxEasterEggHandling?
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let pageUrl = dict["url"] as? String else { return }
        
        let logoURL = dict["logoURL"] as? String
        daxEasterEggHandler?.didExtractLogo(logoURL, from: pageUrl)
    }
}
