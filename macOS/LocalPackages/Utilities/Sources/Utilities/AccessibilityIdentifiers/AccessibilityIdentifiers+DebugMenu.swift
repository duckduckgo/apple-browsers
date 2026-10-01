//
//  AccessibilityIdentifiers+DebugMenu.swift
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

public extension AccessibilityIdentifiers {
    enum DebugMenu {
        /// Parent of **Simulate debug://failure connection error** (`debug://` custom scheme handler debugging).
        public static let failureURLScheme = "DebugMenu.failureURLScheme"
        public static let simulateFailureURLSchemeConnectionError = "DebugMenu.simulateFailureURLSchemeConnectionError"
        public static let openFailureURLSchemeDemoPage = "DebugMenu.openFailureURLSchemeDemoPage"
        /// `debug://failure?alternatingFailures=1` (UI tests only).
        public static let openFailureURLSchemeAlternatingFailuresDemoPage = "DebugMenu.openFailureURLSchemeAlternatingFailuresDemoPage"
        /// `debug://failure?simulatedError=notConnected` (UI tests only).
        public static let openFailureURLSchemeNotConnectedQueryDemoPage = "DebugMenu.openFailureURLSchemeNotConnectedQueryDemoPage"
        /// `debug://failure?simulatedError=hostNotFound` (UI tests only; error kind that must not auto-reload on tab reactivation).
        public static let openFailureURLSchemeHostNotFoundQueryDemoPage = "DebugMenu.openFailureURLSchemeHostNotFoundQueryDemoPage"

        public static let simulateCPMBreakage = "DebugMenu.simulateCPMBreakage"

        /// `MainMenu` updates the menu item title by state; UI tests detect on/off from the title (checkmarks are unreliable in XCUITest).
        public static let failureURLSchemeSimulateConnectionErrorMenuTitleOff = "Simulate debug://failure connection error (Off)"
        public static let failureURLSchemeSimulateConnectionErrorMenuTitleOn = "Simulate debug://failure connection error (On)"
        public static let simulateCPMBreakageMenuTitleOff = "Simulate CPM Messaging Breakage (Off)"
        public static let simulateCPMBreakageMenuTitleOn = "Simulate CPM Messaging Breakage (On)"
    }
}
