//
//  main.swift
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

// MARK: - fd swap (FIRST — before any engine code)
//
// The engine contains stray `print`s that would corrupt a JSON-on-stdout contract. Preserve the
// original stdout as the result-JSON channel, then point fd 1 (where the engine's prints go) at
// stderr. Everything after this that "prints" lands on stderr; result JSON is written explicitly to
// the preserved descriptor by `ResultWriter`.
ResultChannel.fileDescriptor = dup(STDOUT_FILENO)
dup2(STDERR_FILENO, STDOUT_FILENO)

// MARK: - Parse

let parsed: ParsableCommand
do {
    parsed = try PIRDebug.parseAsRoot()
} catch {
    // Help/version requests exit cleanly; everything else is a usage/config error (exit 2).
    let message = PIRDebug.fullMessage(for: error)
    if PIRDebug.exitCode(for: error) == .success {
        if !message.isEmpty { FileHandle.standardError.write(Data((message + "\n").utf8)) }
        exit(CLIExit.success)
    }
    if !message.isEmpty { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    exit(CLIExit.usageError)
}

guard let command = parsed as? CLIRunnable else {
    // A command group invoked without a subcommand — show help and exit cleanly.
    FileHandle.standardError.write(Data((PIRDebug.helpMessage() + "\n").utf8))
    exit(CLIExit.success)
}

// MARK: - Bootstrap NSApplication and run

runInApplication(command)
