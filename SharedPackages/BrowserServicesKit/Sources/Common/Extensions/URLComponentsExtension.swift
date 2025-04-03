//
//  URLComponentsExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

extension URLComponents {

    public func eTLDplus1(tld: TLD) -> String? {
        return tld.eTLDplus1(self.host?.lowercased())
    }

    public func subdomain(tld: TLD) -> String? {
        return tld.extractSubdomain(from: self.host?.lowercased())
    }

    mutating public func eTLDplus1WithPort(tld: TLD) -> String? {
        guard let port = self.port else {
            return tld.eTLDplus1(self.host?.lowercased())
        }

        self.port = nil
        guard let etldPlus1 = tld.eTLDplus1(self.host?.lowercased()) else { return nil }

        return "\(etldPlus1):\(port)"
    }

    mutating public func addingSubdomain(from sourceURLComponents: URLComponents, tld: TLD) {
        guard let sourceURLSubdomain = sourceURLComponents.subdomain(tld: tld)?.droppingWwwPrefix(),
              !sourceURLSubdomain.isEmpty,
              sourceURLSubdomain != "www",
              let eTLDplus1 = eTLDplus1(tld: tld)
        else { return }

        host = [sourceURLSubdomain, eTLDplus1].joined(separator: ".")
    }

    mutating public func addingPort(from sourceURLComponents: URLComponents) {
        port = sourceURLComponents.port
    }

    mutating public func addingQueryItems(from sourceURLComponents: URLComponents) {
        guard let sourceQueryItems = sourceURLComponents.percentEncodedQueryItems else { return }
        percentEncodedQueryItems = (percentEncodedQueryItems ?? []) + sourceQueryItems
    }

    mutating public func addingFragment(from sourceURLComponents: URLComponents) {
        fragment = sourceURLComponents.fragment
    }
}
