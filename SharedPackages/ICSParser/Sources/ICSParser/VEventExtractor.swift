//
//  VEventExtractor.swift
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

/// Locates VEVENT blocks within a VCALENDAR and returns the lines of every block, in document
/// order. The lines are stripped of `BEGIN:VEVENT` / `END:VEVENT` markers.
enum VEventExtractor {

    static func extract(from lines: [String]) throws -> [[String]] {
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else {
            throw ICSParser.Error.notVCalendar
        }

        var blocks: [[String]] = []
        var inBlock = false
        var currentBlock: [String] = []
        for line in lines {
            if line == "BEGIN:VEVENT" {
                inBlock = true
                currentBlock = []
                continue
            }
            if line == "END:VEVENT" {
                if inBlock {
                    blocks.append(currentBlock)
                }
                inBlock = false
                continue
            }
            if inBlock {
                currentBlock.append(line)
            }
        }

        guard !blocks.isEmpty else {
            throw ICSParser.Error.noVEvent
        }
        return blocks
    }
}
