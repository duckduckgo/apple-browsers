//
//  CoreDataErrorsParser.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import CoreData

public class CoreDataErrorsParser {

    public struct ErrorInfo: Equatable {
        public let code: Int
        public let domain: String
        public let entity: String?
        public let property: String?
    }

    public static func parse(error: NSError) -> [ErrorInfo] {

        let unwrapped = unwrapErrorIfNeeded(error)
        return unwrapped.compactMap(checkError(_:))
    }

    private static func unwrapErrorIfNeeded(_ error: NSError) -> [NSError] {
        if let errors = error.userInfo[NSDetailedErrorsKey] as? [NSError] {
            return errors
        }
        if let errors = error.userInfo["NSDetailedErrors"] as? [NSError] {
            return errors
        }
        return [error]
    }

    private static func checkError(_ error: NSError) -> ErrorInfo {
        if let info = checkValidationError(error) {
            return info
        }

        if let info = checkConflictError(error) {
            return info
        }

        return ErrorInfo(code: error.code, domain: error.domain, entity: nil, property: nil)
    }

    private static func checkValidationError(_ error: NSError) -> ErrorInfo? {
        guard let validationInfo = error.userInfo[NSValidationKeyErrorKey] as? String,
           let managedObject = error.userInfo[NSValidationObjectErrorKey] as? NSManagedObject else {
            return nil
        }
        return ErrorInfo(code: error.code,
                         domain: error.domain,
                         entity: managedObject.entity.name,
                         property: validationInfo)
    }

    private static func checkConflictError(_ error: NSError) -> ErrorInfo? {
        guard error.code == NSManagedObjectMergeError,
              let conflicts = error.userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict],
              let firstConflict = conflicts.first else {
            return nil
        }

        return ErrorInfo(code: error.code, domain: error.domain, entity: firstConflict.sourceObject.entity.name, property: nil)
    }

}
