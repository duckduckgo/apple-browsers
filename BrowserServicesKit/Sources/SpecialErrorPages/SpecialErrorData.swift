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
}

public enum SpecialErrorData: Encodable, Equatable {

    enum CodingKeys: CodingKey {
        case kind
        case errorType
        case domain
        case eTldPlus1
        case url
    }

    case ssl(type: SSLErrorType, domain: String, eTldPlus1: String?)
    case maliciousSite(kind: MaliciousSiteProtection.ThreatKind, url: URL)

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
                guard let eTldPlus1 else {
                    assertionFailure("expected eTldPlus1 != nil when kind is .wrongHost")
                    break
                }
                try container.encode(eTldPlus1, forKey: .eTldPlus1)
            }

        case .maliciousSite(kind: let kind, url: let url):
            // https://app.asana.com/0/1206594217596623/1208824527069247/f
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind.errorPageKind, forKey: .kind)
            try container.encode(url, forKey: .url)
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
