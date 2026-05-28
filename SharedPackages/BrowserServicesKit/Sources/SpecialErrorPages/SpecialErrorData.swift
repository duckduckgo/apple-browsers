//
//  SpecialErrorData.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import MaliciousSiteProtection

public enum SpecialErrorKind: String, Encodable {
    case ssl
    case phishing
    case malware
    case scam
    case generalPageProblem
}

public enum SpecialErrorData: Encodable, Equatable {

    enum CodingKeys: CodingKey {
        case kind
        case errorType
        case domain
        case eTldPlus1
        case url
        case title
        case message
        case button
    }

    case ssl(type: SSLErrorType, domain: String, eTldPlus1: String)
    case maliciousSite(kind: MaliciousSiteProtection.ThreatKind, url: URL)
    case generalPageProblem(url: URL, title: String?, message: String?, button: String?)

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .ssl(type: let type, domain: let domain, eTldPlus1: let eTldPlus1):
            try container.encode(SpecialErrorKind.ssl, forKey: .kind)
            try container.encode(type, forKey: .errorType)
            try container.encode(domain, forKey: .domain)

            switch type {
            case .expired, .selfSigned, .invalid: break
            case .wrongHost:
                try container.encode(eTldPlus1, forKey: .eTldPlus1)
            }

        case .maliciousSite(kind: let kind, url: let url):
            // https://app.asana.com/0/1206594217596623/1208824527069247/f
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind.errorPageKind, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .generalPageProblem(url: let url, title: let title, message: let message, button: let button):
            try container.encode(SpecialErrorKind.generalPageProblem, forKey: .kind)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(message, forKey: .message)
            try container.encodeIfPresent(button, forKey: .button)
        }
    }

}

public extension MaliciousSiteProtection.ThreatKind {
    var errorPageKind: SpecialErrorKind {
        switch self {
        case .malware: .malware
        case .phishing: .phishing
        case .scam: .scam
        }
    }
}
