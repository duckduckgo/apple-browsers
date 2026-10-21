//
//  NativeMessagingCommunicator.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Common
import FoundationExtensions
import Foundation
import os.log

protocol NativeMessagingCommunicatorDelegate: AnyObject {

    func nativeMessagingCommunicator(_ nativeMessagingCommunicator: NativeMessagingCommunication, didReceiveMessageData messageData: Data)
    func nativeMessagingCommunicatorProcessDidTerminate(_ nativeMessagingCommunicator: NativeMessagingCommunication)

}

protocol NativeMessagingCommunication: AnyObject {

    func runProxyProcess() throws
    func terminateProxyProcess()

    var delegate: NativeMessagingCommunicatorDelegate? { get set }
    func send(messageData: Data)

}

final class NativeMessagingCommunicator: NSObject, NativeMessagingCommunication {

    let appPath: String
    let arguments: [String]
    let stopsMonitoringAtEOF: () -> Bool

    weak var delegate: NativeMessagingCommunicatorDelegate?

    // MARK: - Running Proxy Process

    private struct ProcessWrapper {
        let process: Process
        let readingHandle: FileHandle
        let writingHandle: FileHandle
    }

    private var process: ProcessWrapper?

    init(appPath: String,
         arguments: [String],
         stopsMonitoringAtEOF: @escaping () -> Bool = { true }) {
        self.appPath = appPath
        self.arguments = arguments
        self.stopsMonitoringAtEOF = stopsMonitoringAtEOF
    }

    func runProxyProcess() throws {
        if process != nil {
            terminateProxyProcess()
        }

        let process = Process()

        let outputPipe = Pipe()
        let outHandle = outputPipe.fileHandleForReading
        // The kill switch is sampled once per launch so the EOF behavior can't change
        // mid-connection and the flag is never read off the main thread
        let stopMonitoringAtEOF = stopsMonitoringAtEOF()
        outHandle.readabilityHandler = { [weak self] fileHandle in
            self?.receiveData(fileHandle, stopMonitoringAtEOF: stopMonitoringAtEOF)
        }

        let inputPipe = Pipe()
        let inputHandle = inputPipe.fileHandleForWriting

        process.executableURL = URL(fileURLWithPath: appPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.terminationHandler = processDidTerminate(_:)

        // Enqueued ahead of any data callback, so the new handle is active
        // before the first message arrives
        dataQueue.async {
            self.accumulatedData = Data()
            self.activeReadingHandle = outHandle
        }

        try process.run()
        Logger.bitWarden.log("NativeMessagingCommunicator: Proxy process running (pid: \(process.processIdentifier, privacy: .public))")

        self.process = ProcessWrapper(process: process, readingHandle: outHandle, writingHandle: inputHandle)
    }

    func terminateProxyProcess() {
        guard let process = process else {
            return
        }
        self.process = nil

        stopMonitoring(process)
        process.process.terminate()
    }

    private func stopMonitoring(_ processWrapper: ProcessWrapper) {
        // Uninstall the readability handler before releasing the handle. The handler's
        // dispatch source keeps the handle alive and keeps firing at EOF otherwise.
        processWrapper.readingHandle.readabilityHandler = nil

        // Drop any partial message so it can't misframe the next proxy's messages
        dataQueue.async {
            self.activeReadingHandle = nil
            self.accumulatedData = Data()
        }
    }

    private func processDidTerminate(_ process: Process) {
        Logger.bitWarden.log("NativeMessagingCommunicator: Proxy process terminated (pid: \(process.processIdentifier, privacy: .public))")

        DispatchQueue.main.async { [weak self] in
            guard let self, let processWrapper = self.process, processWrapper.process == process else {
                // Intentionally terminated or already replaced by a new proxy process
                return
            }
            self.process = nil
            self.stopMonitoring(processWrapper)

            self.delegate?.nativeMessagingCommunicatorProcessDidTerminate(self)
        }
    }

    // MARK: - Sending Messages

    func send(messageData: Data) {
        write(messageData: messageData)
    }

    private func write(messageData: Data) {
        guard let process = process else {
            // Expected transiently: teardown is asynchronous, so a status refresh or
            // credential request can race the proxy's termination
            Logger.bitWarden.log("NativeMessagingCommunicator: Dropping message, proxy process isn't running")
            return
        }

        // Prefix with the length of data
        var messageDataCount = UInt32(messageData.count)
        let messagePrefix = Data(bytes: &messageDataCount, count: MemoryLayout.size(ofValue: messageDataCount))
        let finalMessage = messagePrefix + messageData

        do {
            try process.writingHandle.write(contentsOf: finalMessage)
        } catch {
            // The proxy process can die between termination and its async delegate
            // notification; the legacy non-throwing write would crash here
            Logger.bitWarden.error("NativeMessagingCommunicator: Writing to the proxy process failed")
        }
    }

    // MARK: - Receiving Messages

    private let realisticMessageLength = 200000
    private var accumulatedData = Data()
    // Only accessed on dataQueue; identifies which pipe is allowed to feed accumulatedData
    private var activeReadingHandle: FileHandle?
    private let dataQueue = DispatchQueue(label: "NativeMessagingCommunicator.queue")

    func receiveData(_ fileHandle: FileHandle, stopMonitoringAtEOF: Bool = true) {
        let newData = fileHandle.availableData

        if newData.isEmpty && stopMonitoringAtEOF {
            // Empty data means EOF (the proxy process exited). Stop monitoring,
            // otherwise the readability handler keeps firing and pegs a CPU core.
            Logger.bitWarden.log("NativeMessagingCommunicator: Pipe EOF, monitoring stopped")
            fileHandle.readabilityHandler = nil
            return
        }

        dataQueue.async {
            guard fileHandle === self.activeReadingHandle else {
                // Late data from an already replaced proxy process
                return
            }
            self.accumulatedData.append(newData)
            self.processAccumulatedData()
        }
    }

    private func processAccumulatedData() {
        dataQueue.async {
            repeat {
                let (messageData, remainingData) = self.readMessage(availableData: self.accumulatedData)
                self.accumulatedData = remainingData

                guard let messageData = messageData else {
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    self.delegate?.nativeMessagingCommunicator(self, didReceiveMessageData: messageData)
                }
            } while self.accumulatedData.count >= 2 /*EOF*/
        }
    }

    func readMessage(availableData: Data) -> (messageData: Data?, availableData: Data) {
        guard availableData.count > 0 else { return (nil, availableData: availableData) }

        // First 4 bytes of the message contain the message length
        let dataPrefix = availableData.prefix(4)
        guard dataPrefix.count == 4 else {
            assertionFailure("Wrong format of the message")
            return (nil, availableData)
        }

        let dataPrefixArray = [UInt8](dataPrefix)
        let messageLength = fromByteArray(dataPrefixArray, UInt32.self)

        let dataPostfix = availableData.dropFirst(4)

        if messageLength > dataPostfix.count {
            if messageLength > realisticMessageLength {
                self.accumulatedData = Data()
                return (nil, Data())
            }
            return (nil, availableData)
        }

        let messageData = dataPostfix.prefix(Int(messageLength))
        let availableData = dataPostfix.dropFirst(Int(messageLength))
        return (messageData: messageData, availableData: availableData)
    }

    private func fromByteArray<T>(_ value: [UInt8], _: T.Type) -> T {
        return value.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: T.self, capacity: 1) {
                $0.pointee
            }
        }
    }

}
