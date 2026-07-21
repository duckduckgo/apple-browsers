//
//  OutputOptions.swift
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

import ArgumentParser
import Foundation

/// Where result JSON and the event stream are written.
struct OutputOptions: ParsableArguments {

    @Option(name: .long, help: "Write result JSON to this file instead of stdout.")
    var output: String?

    @Option(name: .long, help: "Write the PIRDebugEvent stream as JSONL to this path. Use '-' to interleave on stderr (NOT stdout — the result channel stays JSON-only).")
    var events: String?

    var resultWriter: ResultWriter {
        ResultWriter(outputPath: output)
    }

    func makeEventsWriter() -> EventsWriter? {
        EventsWriter(path: events)
    }
}
