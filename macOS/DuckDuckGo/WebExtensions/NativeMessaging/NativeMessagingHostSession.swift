//
//  NativeMessagingHostSession.swift
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
import os.log
import WebExtensions

/// Runs one native messaging host process and exchanges framed messages with it.
///
/// The host reads from its standard input and writes to its standard output. Each message
/// carries a 4-byte length prefix. See `NativeMessagingFraming`.
///
/// A sandboxed build cannot launch a host, because the host is a separate executable outside
/// the container. App Store builds are sandboxed, so this only works in the DMG builds.
final class NativeMessagingHostSession {

    enum SessionError: Error {
        case launchFailed(underlying: Error)
        case hostEnded
    }

    /// Called on the main actor for each message the host sends.
    var messageHandler: (@MainActor (Any) -> Void)?

    /// Called on the main actor once, when the host ends or fails.
    var terminationHandler: (@MainActor (Error?) -> Void)?

    let hostName: String

    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private var readTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var didFinish = false

    /// Set when the process ends. The read loop still has to drain the pipe.
    private var exitStatus: Int32?

    init(hostName: String, executable: URL, callerOrigin: String) {
        self.hostName = hostName
        process.executableURL = executable
        // Chrome passes the caller's origin as the first argument, so a host that inspects
        // its arguments sees what it expects.
        process.arguments = [callerOrigin]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
    }

    // MARK: - Lifecycle

    @MainActor
    func start() throws {
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.exitStatus = status

                // Do not finish here. A host often writes its last message and exits at once,
                // and that message explains why it exited. The read loop ends by itself when
                // the pipe reaches EOF, and only then has it seen everything.
                self.finishIfDrainStalls()
            }
        }

        do {
            try process.run()
        } catch {
            throw SessionError.launchFailed(underlying: error)
        }

        Logger.webExtensions.debug("🔗 Host \(self.hostName, privacy: .public) started, pid \(self.process.processIdentifier, privacy: .public)")
        startReadLoop()
        startErrorLoop()
    }

    @MainActor
    func stop() {
        guard !didFinish else { return }
        didFinish = true
        tearDown()
    }

    @MainActor
    private func finish(with error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        tearDown()

        let handler = terminationHandler
        terminationHandler = nil
        messageHandler = nil
        handler?(error)
    }

    /// Cancels the pipe readers, ends the host if it still runs, and closes its input.
    ///
    /// Both ways out of a session go through here, so a host that made the read loop throw
    /// does not stay alive with an open stdin after the session is gone.
    @MainActor
    private func tearDown() {
        readTask?.cancel()
        readTask = nil
        errorTask?.cancel()
        errorTask = nil

        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        try? inputPipe.fileHandleForWriting.close()
    }

    // MARK: - Write

    @MainActor
    func send(_ message: Any) throws {
        let frame = try NativeMessagingFraming.encode(message)
        let handle = inputPipe.fileHandleForWriting

        // Writes go off the main thread: a host that reads slowly must not block the browser.
        Task.detached {
            do {
                try handle.write(contentsOf: frame)
            } catch {
                Logger.webExtensions.error("❌ Write to host failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Read

    private func startReadLoop() {
        let handle = outputPipe.fileHandleForReading
        let name = hostName

        // A strong reference keeps the session alive until the pipe drains. Otherwise the
        // port may release it first, and a final message would go unseen. `stop()` cancels
        // this task, so the reference does not outlive the session's use.
        readTask = Task.detached { [self] in
            do {
                while !Task.isCancelled {
                    guard let prefix = try Self.readExactly(NativeMessagingFraming.prefixSize, from: handle) else {
                        break
                    }
                    let length = try NativeMessagingFraming.decodeLength(prefix)
                    guard length > 0 else { continue }

                    guard let payload = try Self.readExactly(length, from: handle) else { break }
                    let message = try NativeMessagingFraming.decodePayload(payload)

                    await MainActor.run {
                        self.messageHandler?(message)
                    }
                }
                await MainActor.run {
                    self.finishAfterDrain()
                }
            } catch {
                Logger.webExtensions.error("❌ Read from host \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.finish(with: error)
                }
            }
        }
    }

    /// Finishes once the pipe has no more to give, and reports how the host ended.
    @MainActor
    private func finishAfterDrain() {
        guard !didFinish else { return }

        if let exitStatus, exitStatus != 0 {
            // Two causes look the same here. The host may have nothing to talk to, as
            // Bitwarden's proxy does without its desktop app. Or it refused us, as
            // 1Password's does for a browser it does not know. A host that refuses usually
            // says so in its last message or on standard error.
            Logger.webExtensions.error("""
            ❌ Host \(self.hostName, privacy: .public) ended with status \(exitStatus, privacy: .public). \
            Either its companion app is absent, or the host refused us.
            """)
            finish(with: SessionError.hostEnded)
        } else {
            Logger.webExtensions.debug("🔗 Host \(self.hostName, privacy: .public) ended normally")
            finish(with: nil)
        }
    }

    /// Backstop for a host that exits but leaves its output pipe open.
    @MainActor
    private func finishIfDrainStalls() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
            guard let self, !self.didFinish else { return }
            Logger.webExtensions.error("❌ Host \(self.hostName, privacy: .public) ended, and its output never closed")
            self.finishAfterDrain()
        }
    }

    /// Logs whatever the host writes to its standard error.
    ///
    /// A host that refuses the connection usually explains itself here, and that explanation
    /// is the only clue the browser gets.
    private func startErrorLoop() {
        let handle = errorPipe.fileHandleForReading
        let name = hostName

        errorTask = Task.detached {
            while !Task.isCancelled {
                guard let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty else { return }
                let text = String(data: chunk, encoding: .utf8) ?? "(\(chunk.count) bytes)"
                Logger.webExtensions.error("❌ Host \(name, privacy: .public) stderr: \(text, privacy: .public)")
            }
        }
    }

    /// Describes a host message by its `type` fields only.
    ///
    /// Reads exactly `count` bytes, or returns `nil` once the host closes its output.
    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data? {
        var data = Data()
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else {
                return nil
            }
            data.append(chunk)
        }
        return data
    }
}
