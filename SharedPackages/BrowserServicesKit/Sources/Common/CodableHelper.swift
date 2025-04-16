//
//  CodableHelper.swift
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
import os.log

public struct CodableHelper {

    public static func decode<Input: Any, T: Decodable>(from input: Input) -> T? {
        do {
            let json = try JSONSerialization.data(withJSONObject: input)
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            Logger.general.error("Error decoding input: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public static func decode<T: Decodable>(jsonData: Data) -> T? {
        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            Logger.general.error("Error decoding input: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    public static func encode<T: Codable>(_ object: T) -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            return try encoder.encode(object)
        } catch let error {
            Logger.general.error("Error encoding input: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
}

public typealias DecodableHelper = CodableHelper
