//
//  ShowQRCodeViewModel.swift
//  DuckDuckGo
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
import UIKit

struct ShowQRCodeViewModel {

    let codeForDisplayOrPasting: String
    let qrCodeString: String

    var codeForDisplay: String {
        Self.strippingPairingURL(from: codeForDisplayOrPasting)
    }

    func copy() {
        UIPasteboard.general.string = codeForDisplayOrPasting
    }

    private static func strippingPairingURL(from code: String) -> String {
        guard let url = URL(string: code),
              url.scheme?.hasPrefix("http") == true,
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            return code
        }

        let parameters = fragment
            .split(separator: "&")
            .reduce(into: [String: String]()) { result, part in
                let keyValue = part.split(separator: "=", maxSplits: 1)
                guard keyValue.count == 2 else { return }
                result[String(keyValue[0])] = String(keyValue[1])
            }

        return parameters["code2"] ?? parameters["code"] ?? code
    }

}
