//
//  AutofillCryptoProvider.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import CommonCrypto
import CryptoKit
import Security
import SecureStorage

final class AutofillCryptoProvider: SecureStorageCryptoProvider {

    var keychainAccountName: String {
#if os(iOS)
        return "com.duckduckgo.mobile.ios"
#else
        return Bundle.main.bundleIdentifier ?? "com.duckduckgo.macos.browser"
#endif
    }

    var keychainServiceName: String {
        return "DuckDuckGo Secure Vault Hash"
    }

    var passwordSalt: Data {
        return "33EF1524-0DEA-4201-9B51-19230121EADB".data(using: .utf8)!
    }

}
