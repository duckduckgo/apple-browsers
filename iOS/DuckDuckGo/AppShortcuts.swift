//
//  AppShortcuts.swift
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

import AppIntents
import Foundation
import Core

@available(iOS 17.0, *)
struct AppShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: EnableVPNIntent(),
                    phrases: [
                        "Connect \(.applicationName) VPN",
                        "Connect the \(.applicationName) VPN",
                        "Turn \(.applicationName) VPN on",
                        "Turn the \(.applicationName) VPN on",
                        "Turn on \(.applicationName) VPN",
                        "Turn on the \(.applicationName) VPN",
                        "Enable \(.applicationName) VPN",
                        "Enable the \(.applicationName) VPN",
                        "Start \(.applicationName) VPN",
                        "Start the \(.applicationName) VPN",
                        "Start the VPN connection with \(.applicationName)",
                        "Secure my connection with \(.applicationName)",
                        "Protect my connection with \(.applicationName)"
                    ],
                    systemImageName: "globe")
        AppShortcut(intent: DisableVPNIntent(),
                    phrases: [
                        "Disconnect \(.applicationName) VPN",
                        "Disconnect the \(.applicationName) VPN",
                        "Turn \(.applicationName) VPN off",
                        "Turn the \(.applicationName) VPN off",
                        "Turn off \(.applicationName) VPN",
                        "Turn off the \(.applicationName) VPN",
                        "Disable \(.applicationName) VPN",
                        "Disable the \(.applicationName) VPN",
                        "Stop \(.applicationName) VPN",
                        "Stop the \(.applicationName) VPN",
                        "Stop the VPN connection with \(.applicationName)"
                    ],
                    systemImageName: "globe")
        AppShortcut(intent: SearchInAppIntent(),
                    phrases: [
                        "Access \(.applicationName)",
                        "Begin a search in \(.applicationName)",
                        "Begin searching with \(.applicationName)",
                        "Go to \(.applicationName)",
                        "Launch \(.applicationName)",
                        "New \(.applicationName) Search",
                        "Open \(.applicationName)",
                        "Open \(.applicationName) browser",
                        "Open Search in \(.applicationName)",
                        "Search in \(.applicationName)",
                        "Search the web with \(.applicationName)",
                        "Search using \(.applicationName)",
                        "Search with \(.applicationName)",
                        "Start a search in \(.applicationName)",
                        "Start browsing with \(.applicationName)",
                        "Start searching with \(.applicationName)",
                        "Use \(.applicationName) to browse",
                        "Use \(.applicationName) to search"
                    ],
                    shortTitle: "Search",
                    systemImageName: "magnifyingglass"
        )
        AppShortcut(intent: AIChatIntent(),
                    phrases: [
                        "Access Duck AI on \(.applicationName)",
                        "Access \(.applicationName) AI chat",
                        "Access \(.applicationName) Chat",
                        "Ask Duck AI on \(.applicationName)",
                        "Ask \(.applicationName) AI chat",
                        "Ask \(.applicationName) Chat",
                        "Go to Duck AI on \(.applicationName)",
                        "Go to \(.applicationName) AI Chat",
                        "Go to \(.applicationName) Chat",
                        "Launch Duck AI on \(.applicationName)",
                        "Launch \(.applicationName) AI Chat",
                        "Launch \(.applicationName) Chat",
                        "New \(.applicationName) AI Chat",
                        "New \(.applicationName) Chat",
                        "Open Duck AI on \(.applicationName)",
                        "Open \(.applicationName) AI Chat",
                        "Open \(.applicationName) Chat",
                        "Start \(.applicationName) AI chat",
                        "Start \(.applicationName) Chat"
                    ],
                    shortTitle: "Duck.ai Chat",
                    systemImageName: "circle.fill"
        )
    }
}
