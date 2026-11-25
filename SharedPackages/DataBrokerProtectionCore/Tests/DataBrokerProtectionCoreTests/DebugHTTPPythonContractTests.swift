//
//  DebugHTTPPythonContractTests.swift
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

#if os(macOS)
import Darwin
import Foundation
import XCTest
import DataBrokerProtectionCore
import DataBrokerProtectionDebugServer

final class DebugHTTPPythonContractTests: XCTestCase {
    func testPythonClientMatchesNativeRoutesAndResponseShapes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let instance = UUID().uuidString
        let port = try availablePort()
        let services = ContractServices()
        let server = DataBrokerProtectionDebugHTTPServer(provider: services, logReader: services, runManager: services,
                                                         port: port, instanceID: instance)
        server.prerequisiteReader = {
            DebugPrerequisiteResult(status: .credentialProvided, backend: "provided-token", environment: "staging",
                                    pirEnvironment: "staging", pirEndpoint: "https://dbp-staging.duckduckgo.com", authenticated: true)
        }
        try server.start()
        defer { server.stop() }

        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let script = root.appendingPathComponent(".claude/skills/ddg-check-pir/tests/native_contract.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path), script.path)
        let outputURL = directory.appendingPathComponent("python.log")
        XCTAssertTrue(FileManager.default.createFile(atPath: outputURL.path, contents: nil))
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--port", String(port), "--instance", instance, "--evidence-dir", directory.path]
        process.environment = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"]
        process.standardOutput = output
        process.standardError = output
        let finished = expectation(description: "Python contract check finished")
        process.terminationHandler = { _ in finished.fulfill() }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        await fulfillment(of: [finished], timeout: 20)
        guard !process.isRunning else { return }
        let diagnostics = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertEqual(process.terminationStatus, 0, diagnostics)
        XCTAssertEqual(services.mutations, ["scan", "optOut:contract-run:record", "email:contract-run", "continue:contract-run:record"])
        XCTAssertEqual(services.scanRequest?.profile.names.first?.firstName, "Contract")
        XCTAssertEqual(services.scanRequest?.profile.names.first?.lastName, "Person")
        XCTAssertEqual(services.scanRequest?.hidesWebView, true)
    }

    private func availablePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
        }
        guard read == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return UInt16(bigEndian: address.sin_port)
    }
}

private final class ContractServices: DataBrokerProtectionDebugReadProviding, DebugLogReading, DataBrokerProtectionDebugModeRunning {
    let agentVersion = "contract-test"
    let schedulerStateString = "stub"
    let lastSchedulerTrigger: Date? = nil
    let environmentName = "staging"
    let endpointURL = URL(string: "https://dbp-staging.duckduckgo.com")!
    let mainConfigETag: String? = nil
    let lastBrokerJSONUpdateCheck = Date.distantPast
    private let lock = NSLock()
    private var calls: [String] = []
    private var request: DebugModeScanRequest?
    private var status: DebugModeRun.OptOutStatus?
    private var hasLink = false

    var mutations: [String] { lock.withLock { calls } }
    var scanRequest: DebugModeScanRequest? { lock.withLock { request } }

    func brokerProfileQueryData() throws -> [BrokerProfileQueryData] { [] }

    func logLines(since: Date?, category: String?, limit: Int) throws -> [DebugLogLine] {
        [DebugLogLine(timestamp: Date(), level: "info", category: "test", subsystem: "test", process: "fixture",
                      message: "log canary contract-test-credential")]
    }

    func startScan(_ request: DebugModeScanRequest) throws -> DebugModeRun {
        lock.withLock {
            calls.append("scan")
            self.request = request
            return snapshot(activity: .scan)
        }
    }

    func run(id: String) -> DebugModeRun? {
        lock.withLock {
            switch id {
            case "contract-run": return snapshot()
            case "scan-error-run": return snapshot(id: id, scanErrors: ["scan failed"])
            case "opt-out-error-run": return snapshot(id: id, optOutError: "opt-out failed")
            case "opt-out-failed-run": return snapshot(id: id, failedStatus: true)
            case "error-event-run": return snapshot(id: id, eventSummary: "Error: contract")
            case "email-failure-run": return snapshot(id: id, eventSummary: "Email confirmation check failed")
            default: return nil
            }
        }
    }

    func startOptOut(runId: String, resultId: String) throws -> DebugModeRun {
        lock.withLock {
            calls.append("optOut:\(runId):\(resultId)")
            status = .awaitingEmailConfirmation
            return snapshot()
        }
    }

    func checkForEmailConfirmation(runId: String) throws -> DebugModeRun {
        lock.withLock {
            calls.append("email:\(runId)")
            hasLink = true
            return snapshot()
        }
    }

    func continueOptOut(runId: String, resultId: String) throws -> DebugModeRun {
        lock.withLock {
            calls.append("continue:\(runId):\(resultId)")
            status = .confirmed
            return snapshot()
        }
    }

    private func snapshot(id: String = "contract-run", activity: DebugModeRun.Activity? = nil, scanErrors: [String] = [],
                          optOutError: String? = nil, failedStatus: Bool = false, eventSummary: String? = nil) -> DebugModeRun {
        let events = eventSummary.map {
            [DebugModeRun.Event(timestamp: .distantPast, kind: "History", profileQuery: "Contract Person", summary: $0, details: "")]
        } ?? []
        return DebugModeRun(id: id, createdAt: .distantPast, broker: .init(name: "Contract", url: "https://broker.invalid"),
                            profileQueries: ["Contract Person"], activity: activity, scanErrors: scanErrors,
                            results: [.init(id: "record", profileQuery: "Contract Person", name: "Contract Person", age: nil,
                                            addresses: [], profileUrl: "https://record.invalid",
                                            optOutStatus: failedStatus ? .failed : status, optOutError: optOutError,
                                            hasEmailConfirmationLink: hasLink)], events: events)
    }
}
#endif
