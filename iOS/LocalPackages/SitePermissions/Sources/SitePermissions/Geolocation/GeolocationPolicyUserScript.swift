//
//  GeolocationPolicyUserScript.swift
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

import Foundation
import UserScript
import WebKit

/// Keeps sandbox signing and document policy separate from the page's JavaScript realm.
public final class GeolocationPolicyUserScript: NSObject, UserScript {

    public static var bundle: Bundle { .module }

    private static let signingToken = UUID().uuidString + UUID().uuidString

    public lazy var source: String = {
        do {
            return try Self.loadJS("geolocationPolicy",
                                   from: Self.bundle,
                                   withReplacements: ["${SIGNING_TOKEN}": Self.signingToken])
        } catch {
            fatalError("Failed to load JS for GeolocationPolicyUserScript: \(error.localizedDescription)")
        }
    }()

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly = false
    public let messageNames = [String]()
    public var requiresRunInPageContentWorld: Bool { false }

    public override init() {
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}
