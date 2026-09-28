//
//  RemoteMessagingModelTests.swift
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

import CoreData
import Persistence
import XCTest
@testable import RemoteMessaging

/// Entity version hashes of every shipped schema version, as compiled by `momc` from the former
/// `RemoteMessaging.xcdatamodeld`. A mismatch means a shipped version was changed and existing stores
/// would no longer match it — add a new version instead.
final class RemoteMessagingModelTests: XCTestCase {

    func testEveryVersionMatchesShippedVersionHashes() {
        let config = "pymPJvj84GACckbd7SzlgldoIbbe0UNUDgJne2OBayI="
        let messageHashes = [
            "zWOujoS0grgoP3OIZUtZsjBHMYzcB6ebz/u2iT4PocY=",
            "qVbeippNPOdgadVFHsyqre73CNWVw8t5x3i3dbIGjPc=",
            "ok9n/EFRSShDu/HbLCstnR+QZBmjvWZwHys0tDvanZA=",
            "76QkGDdA+cNPwGclCApJhiKx/Rb4Ap06L2Um8DpuOwU=",
        ]
        let versions = [RemoteMessagingModel.v1, RemoteMessagingModel.v2, RemoteMessagingModel.v3, RemoteMessagingModel.v4]

        for (index, (version, messageHash)) in zip(versions, messageHashes).enumerated() {
            let model = NSManagedObjectModel(entities: version())
            XCTAssertEqual(model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, [
                "RemoteMessageManagedObject": messageHash,
                "RemoteMessagingConfigManagedObject": config,
            ], "RemoteMessaging v\(index + 1)")
        }
    }

    func testCurrentModelIsLatestVersionBoundToManagedObjectSubclasses() {
        let current = VersionedManagedObjectModel.remoteMessaging.current

        XCTAssertEqual(current.entityVersionHashesByName, NSManagedObjectModel(entities: RemoteMessagingModel.v4()).entityVersionHashesByName)
        XCTAssertEqual(current.entitiesByName.mapValues(\.managedObjectClassName), [
            "RemoteMessageManagedObject": NSStringFromClass(RemoteMessageManagedObject.self),
            "RemoteMessagingConfigManagedObject": NSStringFromClass(RemoteMessagingConfigManagedObject.self),
        ])
    }
}
