//
//  NativeMessagingHostProcess.swift
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

/// Launches a native messaging host the way Chrome does: with responsibility for it disclaimed, so the host
/// is its own responsible process. `Process` can't do that, and macOS 15 kills Apple's iCloud Passwords
/// helper without it.
final class NativeMessagingHostProcess {

    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    /// Private API, so it's looked up at runtime: without it the host launches undisclaimed.
    private static let setDisclaim: SetDisclaim? = dynamicSymbol(named: "responsibility_spawnattrs_setdisclaim")

    /// Called on the main queue once, with the exit code, or the signal that ended the host.
    var terminationHandler: ((Int32) -> Void)?

    private(set) var processIdentifier: pid_t = 0
    private(set) var terminationStatus: Int32?
    var isRunning: Bool { processIdentifier != 0 && terminationStatus == nil }

    private let executable: URL
    private let arguments: [String]
    private var exitSource: DispatchSourceProcess?

    init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    @MainActor
    func run(standardInput: Pipe, standardOutput: Pipe, standardError: Pipe) throws {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Like `Process`, don't leak the browser's other descriptors into the host.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        _ = Self.setDisclaim?(&attributes, 1)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, standardInput.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, standardOutput.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, standardError.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable.path, &fileActions, &attributes, argv, environ)
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
        }
        processIdentifier = pid

        // The host owns these ends now. Holding them would hide its EOF, and its exit from our writes.
        try? standardInput.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()

        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        // Holds `self` until the host is reaped, so it never lingers as a zombie.
        source.setEventHandler { [self] in reap() }
        exitSource = source
        source.resume()
    }

    func terminate() {
        guard isRunning else { return }
        kill(processIdentifier, SIGTERM)
    }

    private func reap() {
        var status: Int32 = 0
        guard terminationStatus == nil, waitpid(processIdentifier, &status, WNOHANG) == processIdentifier else { return }

        // Like `Process`: the exit code, or the signal for a host that was killed.
        let signal = status & 0x7f
        let exitStatus = signal == 0 ? (status >> 8) & 0xff : signal
        terminationStatus = exitStatus
        exitSource?.cancel()
        exitSource = nil

        let handler = terminationHandler
        terminationHandler = nil
        handler?(exitStatus)
    }
}
