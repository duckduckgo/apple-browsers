//
//  URLInputClassifier.swift
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

import Common
import Foundation
import FoundationExtensions
import Network

public enum URLInputClassifier {

    public static func webURL(from text: String) -> URL? {
        guard var url = URL(string: text) else { return nil }

        switch url.navigationalScheme {
        case .http, .https, .duck:
            break
        case .none:
            guard let urlWithScheme = URL(string: URL.NavigationalScheme.http.separated() + text),
                  let host = urlWithScheme.host else {
                return nil
            }
            guard host.contains(".") || host == .localhost else {
                return nil
            }
            if IPv4Address(host) != nil {
                guard host.split(separator: ".").count == 4 else {
                    return nil
                }
            }
            url = urlWithScheme
        default:
            return nil
        }

        guard url.host?.isValidHost == true else { return nil }
        return url
    }

    public static func isValidAddressBarURLInput(_ text: String) -> Bool {
        !text.contains(where: { $0.isWhitespace }) && webURL(from: text) != nil
    }
}
