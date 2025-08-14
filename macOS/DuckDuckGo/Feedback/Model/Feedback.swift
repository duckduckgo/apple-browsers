//
//  Feedback.swift
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
import QuartzCore

struct Feedback {

    enum Category {
        case generalFeedback
        case designFeedback
        case bug
        case featureRequest
        case other
        case usability
        case dataImport
    }

    let category: Category
    let comment: String
    let appVersion: String
    let osVersion: String
    let subcategory: String

    init(category: Category,
         comment: String,
         appVersion: String,
         osVersion: String,
         subcategory: String = "") {
        self.category = category
        self.comment = comment
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.subcategory = subcategory
    }
}

extension Feedback {

    static func from(selectedPillIds: [String],
                     text: String,
                     appVersion: String,
                     category: Feedback.Category,
                     problemCategory: ProblemCategory?) -> Feedback {
        let selectedOptionsString = selectedPillIds.joined(separator: ",")
        let description = text.isEmpty ? category.toString : text
        var subcategory = ""

        if let problemCategory = problemCategory {
            subcategory = "\(problemCategory.id),\(selectedOptionsString)"
        } else {
            subcategory = "\(selectedOptionsString)"
        }

        return Feedback(category: category,
                        comment: description,
                        appVersion: appVersion,
                        osVersion: "\(ProcessInfo.processInfo.operatingSystemVersion)",
                        subcategory: subcategory)
    }
}

extension Feedback.Category {
    var toString: String {
        switch self {
        case .bug:
            return "Via Report a Problem Form"
        case .featureRequest:
            return "Via Request New Feature Form"
        default:
            return "other"
        }
    }
}
