//
//  Logger+LogViewer.swift
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

import os

public extension Logger {
    static var logViewer: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "LogViewer")
    }()
    
    static var networking: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "Networking")
    }()
    
    static var privacy: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "Privacy")
    }()
    
    static var database: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "Database")
    }()
    
    static var search: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "Search")
    }()
    
    static var webView: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "WebView")
    }()
    
    static var ui: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "UI")
    }()
    
    static var auth: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "Auth")
    }()
    
    static var sync: Logger = {
        Logger(subsystem: "com.duckduckgo.mobile.ios", category: "Sync")
    }()
}
