//
//  AIChatLeftoverImagesPixel.swift
//  DuckDuckGo
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

import AIChat
import Foundation
import PixelKit

/// Reports the one-time removal of Duck.ai images WebKit left on disk, so we know when the cleanup can be dropped.
enum AIChatLeftoverImagesPixel: PixelKit.Event {

    case removed(filesRemoved: Int)
    case removalFailed(Error)

    var name: String {
        switch self {
        case .removed: return "aichat_leftover-images_removed"
        case .removalFailed: return "aichat_leftover-images_removal_failed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .removed(let filesRemoved): return ["files_removed": Self.bucket(filesRemoved)]
        case .removalFailed: return nil
        }
    }

    var error: NSError? {
        switch self {
        case .removed: return nil
        case .removalFailed(let error): return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    static func bucket(_ count: Int) -> String {
        switch count {
        case 0: return "0"
        case 1...10: return "1-10"
        case 11...50: return "11-50"
        case 51...200: return "51-200"
        default: return "201+"
        }
    }
}

struct AIChatLeftoverImagesPixelReporter {

    let pixelFiring: (any PixelKitFiring)?

    func report(_ cleanup: AIChatBlobCleanupResult) {
        if let error = cleanup.error {
            pixelFiring?.fire(AIChatLeftoverImagesPixel.removalFailed(error), frequency: .dailyAndCount)
        }
        pixelFiring?.fire(AIChatLeftoverImagesPixel.removed(filesRemoved: cleanup.filesRemoved), frequency: .dailyAndCount)
    }
}
