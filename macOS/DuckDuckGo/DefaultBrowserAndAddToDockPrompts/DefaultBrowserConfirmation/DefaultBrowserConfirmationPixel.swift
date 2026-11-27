//
//  DefaultBrowserConfirmationPixel.swift
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

import Foundation
import PixelKit

/// See definitions in `default-browser-and-dock-prompt-win-back.json5`
enum DefaultBrowserConfirmationPixel: PixelKit.Event, Equatable {

    case confirmed(source: DefaultBrowserConfirmationSource, check: DefaultBrowserConfirmationCheck)
    case notConfirmed(source: DefaultBrowserConfirmationSource)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .confirmed(let source, _):
            return "\(source.rawValue)_default-confirmed_macos"
        case .notConfirmed(let source):
            return "\(source.rawValue)_default-not-confirmed_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .confirmed(_, let check):
            return ["check": check.rawValue]
        case .notConfirmed:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}

enum DefaultBrowserConfirmationDebugPixel: PixelKit.Event {

    case pendingConfirmationReadFailed(source: DefaultBrowserConfirmationSource, error: Error)
    case pendingConfirmationWriteFailed(source: DefaultBrowserConfirmationSource, error: Error)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .pendingConfirmationReadFailed(let source, _):
            return "\(source.rawValue)_pending-confirmation_read-failed_macos"
        case .pendingConfirmationWriteFailed(let source, _):
            return "\(source.rawValue)_pending-confirmation_write-failed_macos"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: NSError? {
        switch self {
        case .pendingConfirmationReadFailed(_, let error), .pendingConfirmationWriteFailed(_, let error):
            return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        nil
    }
}
