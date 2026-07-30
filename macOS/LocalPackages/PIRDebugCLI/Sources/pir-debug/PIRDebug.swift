//
//  PIRDebug.swift
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

/// Root command. Drives the macOS PIR/DBP debug engine (PIRDebugKit) headless from a bare,
/// unsigned executable — no app bundle, no entitlements.
struct PIRDebug: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "pir-debug",
        abstract: "Headless driver for the PIR/DBP debug engine (scan, opt-out, disposable email, rule/script overrides).",
        discussion: """
        I/O contract:
          • stdout  — result JSON only (kept pure via an fd-swap before the engine starts).
          • stderr  — progress logs and the engine's stray prints.
          • --output <path>  writes result JSON to a file instead of stdout.
          • --events <path>  writes the PIRDebugEvent stream as JSONL. NOTE: '--events -' sends the
            stream to STDERR (interleaved), not stdout — this inverts the usual '-' convention so the
            result channel stays JSON-only.

        Exit codes: 0 success (incl. clean zero-record scan), 1 operation failed, 2 usage/config
        error, 3 timeout.
        """,
        subcommands: [
            ScanCommand.self,
            OptOutCommand.self,
            EmailCommand.self,
            AuthCommand.self,
            ValidateCommand.self,
            ListBrokersCommand.self,
            FetchRulesCommand.self,
            ServeCommand.self,
        ])
}
