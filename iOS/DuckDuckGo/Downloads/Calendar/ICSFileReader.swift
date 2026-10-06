//
//  ICSFileReader.swift
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

import Foundation
import ICSParser

/// Pure classifier for a `.ics` file URL. No side effects — callers decide what to do
/// with the outcome (present editor, show toast, fire pixel, …).
enum ICSFileReader {

    enum Outcome {
        case singleEvent(ICSEvent)
        case multipleEvents
        case unrecognizedTimeZone
        case parseFailure
    }

    struct Result {
        let outcome: Outcome
        let warnings: [ICSParser.Warning]
    }

    static func read(at url: URL) -> Result {
        guard let data = try? Data(contentsOf: url) else {
            return Result(outcome: .parseFailure, warnings: [])
        }
        do {
            let parsed = try ICSParser.parse(data: data)
            let outcome: Outcome = parsed.events.count == 1
                ? .singleEvent(parsed.events[0])
                : .multipleEvents
            return Result(outcome: outcome, warnings: parsed.warnings)
        } catch ICSParser.Error.unrecognizedTimeZone(_) {
            return Result(outcome: .unrecognizedTimeZone, warnings: [])
        } catch {
            return Result(outcome: .parseFailure, warnings: [])
        }
    }
}
