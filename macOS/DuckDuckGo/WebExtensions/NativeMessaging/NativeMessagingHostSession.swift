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
    let diagnosticIdentifier = String(UUID().uuidString.prefix(8))

    private let createdAt = Date()
    private var queuedMessageCount = 0
    private var receivedMessageCount = 0

    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private var didFinish = false

    /// Serial, so frames are written to the host in send order and never interleave.
    private let writeQueue = DispatchQueue(label: "com.duckduckgo.native-messaging.host-write")

    /// Bytes the host wrote that don't make a whole message yet. Only the output pipe's
    /// readability handler touches it, and that handler never runs concurrently with itself.
    private var outputBuffer = Data()

    /// Set when the process ends. The output pipe may still hold messages.
    private var exitStatus: Int32?

    /// Set when the output pipe reaches EOF, so the host has nothing more to say.
    private var outputDidClose = false

    /// Prepares a host process.
    ///
    /// - Parameters:
    ///   - hostName: The name the extension asked for, which is also the manifest's `name`.
    ///   - executable: The binary the host manifest's `path` names.
    ///   - callerOrigin: The origin the host sees as its first argument. Chrome passes
    ///     `chrome-extension://<id>/` there, and a host that has an `allowed_origins` list
    ///     matches the argument against it and quits when it finds no match. So this is
    ///     normally the extension's Chrome origin rather than our own `webkit-extension://`
    ///     base URL. `NativeMessagingHandler` picks the value.
    init(hostName: String, executable: URL, callerOrigin: String) {
        self.hostName = hostName
        process.executableURL = executable
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
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeMainThread {
                    guard let self else { return }
                    self.exitStatus = status
                    Logger.webExtensions.info("""
                    [NativeMessaging] process-exited session=\(self.diagnosticIdentifier, privacy: .public) \
                    host=\(self.hostName, privacy: .public) status=\(status) outputClosed=\(self.outputDidClose)
                    """)

                    // Finish only once the output has closed. A host often writes its last message
                    // and exits at once, and that message explains why it exited.
                    if self.outputDidClose {
                        self.finishAfterDrain()
                    } else {
                        self.finishIfDrainStalls()
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            Logger.webExtensions.error("""
            [NativeMessaging] launch-failed session=\(self.diagnosticIdentifier, privacy: .public) \
            host=\(self.hostName, privacy: .public) errorDomain=\((error as NSError).domain, privacy: .public) \
            errorCode=\((error as NSError).code)
            """)
            throw SessionError.launchFailed(underlying: error)
        }

        Logger.webExtensions.info("""
        [NativeMessaging] started session=\(self.diagnosticIdentifier, privacy: .public) \
        host=\(self.hostName, privacy: .public) pid=\(self.process.processIdentifier)
        """)
        startReadLoop()
        startErrorLoop()
    }

    @MainActor
    func stop() {
        guard !didFinish else { return }
        didFinish = true
        Logger.webExtensions.info("""
        [NativeMessaging] stopped session=\(self.diagnosticIdentifier, privacy: .public) \
        host=\(self.hostName, privacy: .public) queued=\(self.queuedMessageCount) received=\(self.receivedMessageCount) \
        elapsedMs=\(Int(Date().timeIntervalSince(self.createdAt) * 1000))
        """)
        tearDown()
    }

    @MainActor
    private func finish(with error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        Logger.webExtensions.info("""
        [NativeMessaging] finished session=\(self.diagnosticIdentifier, privacy: .public) \
        host=\(self.hostName, privacy: .public) failed=\(error != nil) \
        queued=\(self.queuedMessageCount) received=\(self.receivedMessageCount) \
        elapsedMs=\(Int(Date().timeIntervalSince(self.createdAt) * 1000))
        """)
        tearDown()

        let handler = terminationHandler
        terminationHandler = nil
        messageHandler = nil
        handler?(error)
    }

    /// Stops reading the pipes, ends the host if it still runs, and closes its input.
    ///
    /// Both ways out of a session go through here, so a host that sent something unreadable
    /// does not stay alive with an open stdin after the session is gone.
    @MainActor
    private func tearDown() {
        // Removing the handlers also releases the session they hold.
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

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
        queuedMessageCount += 1
        let sequence = queuedMessageCount
        let identifier = diagnosticIdentifier
        Logger.webExtensions.debug("""
        [NativeMessaging] write-queued session=\(identifier, privacy: .public) \
        sequence=\(sequence) framedBytes=\(frame.count)
        """)

        // Writes go off the main thread, so a host that reads slowly cannot block the browser.
        // They go through one serial queue, so frames reach the host in the order the extension
        // posted them and never interleave. A host that expects a handshake in order fails when
        // a later frame overtakes an earlier one.
        writeQueue.async {
            do {
                try handle.write(contentsOf: frame)
                Logger.webExtensions.debug("""
                [NativeMessaging] write-completed session=\(identifier, privacy: .public) \
                sequence=\(sequence) framedBytes=\(frame.count)
                """)
            } catch {
                Logger.webExtensions.error("""
                [NativeMessaging] write-failed session=\(identifier, privacy: .public) \
                sequence=\(sequence) errorDomain=\((error as NSError).domain, privacy: .public) errorCode=\((error as NSError).code)
                """)
            }
        }
    }

    // MARK: - Read

    private func startReadLoop() {
        let name = hostName

        // The handler holds the session strongly, so it lives until the pipe drains. Otherwise the
        // port may release it first, and a final message would go unseen. EOF, an unreadable
        // message and `tearDown()` all remove the handler, which releases the session.
        outputPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            guard let chunk = Self.readAvailableData(from: handle) else {
                handle.readabilityHandler = nil
                DispatchQueue.main.async {
                    MainActor.assumeMainThread { self.didCloseOutput() }
                }
                return
            }

            outputBuffer.append(chunk)
            let (messages, error) = takeMessages()
            Logger.webExtensions.debug("""
            [NativeMessaging] read session=\(self.diagnosticIdentifier, privacy: .public) \
            bytes=\(chunk.count) messages=\(messages.count) bufferedBytes=\(self.outputBuffer.count) failed=\(error != nil)
            """)
            if let error {
                handle.readabilityHandler = nil
                Logger.webExtensions.error("""
                [NativeMessaging] read-failed session=\(self.diagnosticIdentifier, privacy: .public) host=\(name, privacy: .public) \
                errorDomain=\((error as NSError).domain, privacy: .public) errorCode=\((error as NSError).code)
                """)
            }
            guard !messages.isEmpty || error != nil else { return }

            // One hop for all of them, in order. Separate tasks could deliver them out of order.
            // The messages that came before an unreadable one still go first.
            DispatchQueue.main.async {
                MainActor.assumeMainThread {
                    for message in messages where !self.didFinish {
                        self.receivedMessageCount += 1
                        Logger.webExtensions.debug("""
                        [NativeMessaging] host-to-extension session=\(self.diagnosticIdentifier, privacy: .public) \
                        sequence=\(self.receivedMessageCount) handlerPresent=\(self.messageHandler != nil)
                        """)
                        self.messageHandler?(message)
                    }
                    if let error {
                        self.finish(with: error)
                    }
                }
            }
        }
    }

    /// Removes every whole message from the front of `outputBuffer`, and leaves a partial one for
    /// the next read. Stops at the first message it can't read, and returns those before it.
    private func takeMessages() -> (messages: [Any], error: Error?) {
        var messages: [Any] = []
        do {
            while outputBuffer.count >= NativeMessagingFraming.prefixSize {
                let length = try NativeMessagingFraming.decodeLength(outputBuffer.prefix(NativeMessagingFraming.prefixSize))
                let frameSize = NativeMessagingFraming.prefixSize + length
                guard outputBuffer.count >= frameSize else { break }

                let payload = Data(outputBuffer.dropFirst(NativeMessagingFraming.prefixSize).prefix(length))
                outputBuffer = Data(outputBuffer.dropFirst(frameSize))
                if length > 0 {
                    messages.append(try NativeMessagingFraming.decodePayload(payload))
                }
            }
        } catch {
            return (messages, error)
        }
        return (messages, nil)
    }

    /// Finishes once the host has also exited, and waits briefly for that.
    ///
    /// EOF on the output pipe and `Process` reporting the exit race each other, and a host's exit
    /// status is what tells one that failed from one that ended normally. A host that closed its
    /// output and stayed up is finished after a second anyway.
    @MainActor
    private func didCloseOutput() {
        guard !didFinish else { return }
        outputDidClose = true
        Logger.webExtensions.info("""
        [NativeMessaging] output-closed session=\(self.diagnosticIdentifier, privacy: .public) \
        host=\(self.hostName, privacy: .public) bufferedBytes=\(self.outputBuffer.count)
        """)

        if exitStatus != nil || !process.isRunning {
            finishAfterDrain()
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
                self.finishAfterDrain()
            }
        }
    }

    /// Finishes once the pipe has no more to give, and reports how the host ended.
    @MainActor
    private func finishAfterDrain() {
        guard !didFinish else { return }

        // The termination handler may not have run yet. The process still carries the status,
        // and without it a host that failed looks like one that ended well.
        if exitStatus == nil, !process.isRunning {
            exitStatus = process.terminationStatus
        }

        if let exitStatus, exitStatus != 0 {
            // Two causes look the same here. The host may have nothing to talk to, such as a
            // companion app that is not running. Or it refused us, as a host does for a caller
            // it does not know. A host that refuses usually says so in its last message or on
            // standard error.
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
        let name = hostName

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            guard let chunk = Self.readAvailableData(from: handle) else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(data: chunk, encoding: .utf8) ?? "(\(chunk.count) bytes)"
            Logger.webExtensions.error("❌ Host \(name, privacy: .public) stderr: \(text, privacy: .public)")
        }
    }

    /// Reads what the pipe holds, or returns `nil` once the host closes it.
    ///
    /// This calls `read(2)` rather than `availableData`, which raises an Objective-C exception on
    /// a read error, and Swift can't catch that. The readability handler only runs when there is
    /// something to read, so this doesn't block.
    private static func readAvailableData(from handle: FileHandle) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var count: Int
        repeat {
            count = read(handle.fileDescriptor, &buffer, buffer.count)
        } while count < 0 && errno == EINTR

        // 0 is EOF. A read error also ends the host's output.
        guard count > 0 else { return nil }
        return Data(buffer[..<count])
    }
}
