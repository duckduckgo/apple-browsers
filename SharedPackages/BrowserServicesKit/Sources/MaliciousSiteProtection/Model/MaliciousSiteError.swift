//
//  MaliciousSiteError.swift
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

public struct MaliciousSiteError: Error, Equatable {

    public enum Code: Int {
        case phishing = 1
        case malware = 2
        case scam = 3
    }
    public let code: Code
    public let failingUrl: URL

    public init(code: Code, failingUrl: URL) {
        self.code = code
        self.failingUrl = failingUrl
    }

    public init(threat: ThreatKind, failingUrl: URL) {
        let code: Code
        switch threat {
        case .phishing:
            code = .phishing
        case .malware:
           code = .malware
        case .scam:
            code = .scam
        }
        self.init(code: code, failingUrl: failingUrl)
    }

    public var threatKind: ThreatKind {
        switch code {
        case .phishing: .phishing
        case .malware: .malware
        case .scam: .scam
        }
    }

}

extension MaliciousSiteError: _ObjectiveCBridgeableError {

    public init?(_bridgedNSError error: NSError) {
        guard error.domain == MaliciousSiteError.errorDomain,
              let code = Code(rawValue: error.code),
              let failingUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL else { return nil }
        self.code = code
        self.failingUrl = failingUrl
    }

}

extension MaliciousSiteError: LocalizedError {

    public var errorDescription: String? {
        switch code {
        case .phishing:
            return "Phishing detected"
        case .malware:
             return "Malware detected"
        case .scam:
            return "Scam Detected"
        }
    }

}

extension MaliciousSiteError: CustomNSError {
    public static let errorDomain: String = "MaliciousSiteError"

    public var errorCode: Int {
        code.rawValue
    }

    public var errorUserInfo: [String: Any] {
        [
            NSURLErrorFailingURLErrorKey: failingUrl,
            NSLocalizedDescriptionKey: errorDescription!
        ]
    }

}
