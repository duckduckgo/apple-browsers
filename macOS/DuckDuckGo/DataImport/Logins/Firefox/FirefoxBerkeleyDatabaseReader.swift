//
//  FirefoxBerkeleyDatabaseReader.swift
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

import CommonObjCExtensions
import Foundation

enum FirefoxBerkeleyDatabaseReader {

    static func readDatabase(at databasePath: String) throws -> [String: Data] {
        guard let db = databasePath.withCString({ pathPointer in
            dbopen(pathPointer, O_RDONLY, O_RDONLY, DB_HASH, nil)
        }) else { throw NSError(domain: "FirefoxBerkeleyDatabaseReaderError", code: Int(errno)) }

        var results: [String: Data] = [:]

        var currentKeyDBT = DBT()
        var currentDataDBT = DBT()

        // R_FIRST positions at the first record; R_NEXT advances. macOS 26's libdb
        // no longer treats R_NEXT-without-a-cursor as R_FIRST, so be explicit.
        var flag = UInt32(R_FIRST)
        while db.pointee.seq(db, &currentKeyDBT, &currentDataDBT, flag) == 0 {
            flag = UInt32(R_NEXT)
            let currentKeyData = currentKeyDBT.data.withMemoryRebound(to: UInt8.self, capacity: currentKeyDBT.size) { pointer in
                Data(bytes: pointer, count: currentKeyDBT.size)
            }
            let currentData = currentDataDBT.data.withMemoryRebound(to: UInt8.self, capacity: currentDataDBT.size) { pointer in
                Data(bytes: pointer, count: currentDataDBT.size)
            }

            if currentKeyData == Self.firefoxASN1Key {
                results["data"] = currentData
            } else if let currentKeyString = currentKeyData.utf8String() {
                results[currentKeyString] = currentData
            }
        }

        return results
    }

    private static let firefoxASN1Key = Data([0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
}
