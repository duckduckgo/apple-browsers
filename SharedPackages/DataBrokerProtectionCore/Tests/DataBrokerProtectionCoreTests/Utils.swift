//
//  Utils.swift
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

import Foundation

extension HTTPURLResponse {
    static let ok = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 200, httpVersion: nil, headerFields: [String: String]())!
    static let notModified = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 304, httpVersion: nil, headerFields: [String: String]())!
    static let noAuth = HTTPURLResponse(url: URL(string: "http://www.example.com")!, statusCode: 401, httpVersion: nil, headerFields: [String: String]())!
}
