//
//  ExtensionMessage.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public enum ExtensionMessage: RawRepresentable {
    public typealias RawValue = Data

    enum Name: UInt8 {
        // This is actually an improved way to send messages.
        // Please avoid adding new messages to this enum, and instead
        // add them to `ExtensionRequest`
        case request = 255

        case resetAllState = 0
        case getRuntimeConfiguration
        case getLastErrorMessage
        case isHavingConnectivityIssues
        case setSelectedServer
        case getServerLocation
        case getServerAddress
        case expireRegistrationKey
        case setKeyValidity
        case triggerTestNotification
        case setExcludedRoutes
        case setIncludedRoutes
        case simulateTunnelFailure
        case simulateTunnelFatalError
        case simulateTunnelMemoryOveruse
        case simulateConnectionInterruption
        case getDataVolume
        case startSnooze
        case cancelSnooze
    }

    // This is actually an improved way to send messages.
    // Please avoid adding new messages to this enum, and instead
    // add them to `ExtensionRequest`
    case request(_ request: ExtensionRequest)

    // important: Preserve this order because Message Name is represented by Int value
    case resetAllState
    case getRuntimeConfiguration
    case getLastErrorMessage
    case isHavingConnectivityIssues
    case setSelectedServer(String?)
    case getServerLocation
    case getServerAddress
    case expireRegistrationKey
    case setKeyValidity(TimeInterval?)
    case triggerTestNotification
    case setExcludedRoutes([IPAddressRange])
    case setIncludedRoutes([IPAddressRange])
    case simulateTunnelFailure
    case simulateTunnelFatalError
    case simulateTunnelMemoryOveruse
    case simulateConnectionInterruption
    case getDataVolume
    case startSnooze(TimeInterval)
    case cancelSnooze

    public init?(rawValue data: Data) {
        let name = data.first.flatMap(Name.init(rawValue:))
        switch name {
        case .request:
            guard let request = try? JSONDecoder().decode(ExtensionRequest.self, from: data[1...]) else {
                return nil
            }

            self = .request(request)
        case .resetAllState:
            self = .resetAllState
        case .getRuntimeConfiguration:
            self = .getRuntimeConfiguration
        case .getLastErrorMessage:
            self = .getLastErrorMessage
        case .isHavingConnectivityIssues:
            self = .isHavingConnectivityIssues
        case .setSelectedServer:
            guard data.count > 1 else {
                self = .setSelectedServer(nil)
                return
            }
            let serverName = ExtensionMessageString(rawValue: data[1...])
            self = .setSelectedServer(serverName?.value)

        case .getServerLocation:
            self = .getServerLocation
        case .getServerAddress:
            self = .getServerAddress
        case .expireRegistrationKey:
            self = .expireRegistrationKey
        case .setKeyValidity:
            guard data.count == MemoryLayout<UInt>.size + 1 else { return nil }
            let uintValue = data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 1, as: UInt.self)
            }
            let keyValidity = TimeInterval(uintValue.littleEndian)

            self = .setKeyValidity(keyValidity)

        case .triggerTestNotification:
            self = .triggerTestNotification

        case .setExcludedRoutes,
             .setIncludedRoutes:
            do {
                let routes = data.count > 1 ? try JSONDecoder().decode([IPAddressRange].self, from: data[1...]) : []
                self = (name == .setExcludedRoutes) ? .setExcludedRoutes(routes) : .setIncludedRoutes(routes)
            } catch {
                assertionFailure("\(error)")
                return nil
            }

        case .simulateTunnelFailure:
            self = .simulateTunnelFailure

        case .simulateTunnelFatalError:
            self = .simulateTunnelFatalError

        case .simulateTunnelMemoryOveruse:
            self = .simulateTunnelMemoryOveruse

        case .simulateConnectionInterruption:
            self = .simulateConnectionInterruption

        case .getDataVolume:
            self = .getDataVolume

        case .startSnooze:
            guard data.count == MemoryLayout<UInt>.size + 1 else { return nil }
            let uintValue = data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 1, as: UInt.self)
            }
            let snoozeDuration = TimeInterval(uintValue.littleEndian)

            self = .startSnooze(snoozeDuration)

        case .cancelSnooze:
            self = .cancelSnooze

        case .none:
            assertionFailure("Invalid data")
            return nil
        }
    }

    // TO BE: Replaced with auto case name generating Macro when Xcode 15
    private var name: Name {
        switch self {
        case .request: return .request
        case .resetAllState: return .resetAllState
        case .getRuntimeConfiguration: return .getRuntimeConfiguration
        case .getLastErrorMessage: return .getLastErrorMessage
        case .isHavingConnectivityIssues: return .isHavingConnectivityIssues
        case .setSelectedServer: return .setSelectedServer
        case .getServerLocation: return .getServerLocation
        case .getServerAddress: return .getServerAddress
        case .expireRegistrationKey: return .expireRegistrationKey
        case .setKeyValidity: return .setKeyValidity
        case .triggerTestNotification: return .triggerTestNotification
        case .setExcludedRoutes: return .setExcludedRoutes
        case .setIncludedRoutes: return .setIncludedRoutes
        case .simulateTunnelFailure: return .simulateTunnelFailure
        case .simulateTunnelFatalError: return .simulateTunnelFatalError
        case .simulateTunnelMemoryOveruse: return .simulateTunnelMemoryOveruse
        case .simulateConnectionInterruption: return .simulateConnectionInterruption
        case .getDataVolume: return .getDataVolume
        case .startSnooze: return .startSnooze
        case .cancelSnooze: return .cancelSnooze
        }
    }

    public var rawValue: Data {
        var encoder: (inout Data) -> Void = { _ in }
        switch self {
        case .request(let request):
            encoder = {
                do {
                    try $0.append(JSONEncoder().encode(request))
                } catch {
                    assertionFailure("could not encode request: \(error)")
                }
            }
        case .setSelectedServer(.some(let serverName)):
            encoder = {
                $0.append(ExtensionMessageString(serverName).rawValue)
            }
        case .setKeyValidity(.some(let validity)):
            encoder = { data in
                withUnsafeBytes(of: UInt(validity).littleEndian) { buffer in
                    data.append(Data(buffer))
                }
            }
        case .setExcludedRoutes(let routes),
             .setIncludedRoutes(let routes):
            guard !routes.isEmpty else { break }
            encoder = {
                do {
                    try $0.append(JSONEncoder().encode(routes))
                } catch {
                    assertionFailure("could not encode routes: \(error)")
                }
            }
        case .startSnooze(let interval):
            encoder = { data in
                withUnsafeBytes(of: UInt(interval).littleEndian) { buffer in
                    data.append(Data(buffer))
                }
            }
        case .setSelectedServer(.none),
             .setKeyValidity(.none),
             .resetAllState,
             .getRuntimeConfiguration,
             .getLastErrorMessage,
             .isHavingConnectivityIssues,
             .getServerLocation,
             .getServerAddress,
             .expireRegistrationKey,
             .triggerTestNotification,
             .simulateTunnelFailure,
             .simulateTunnelFatalError,
             .simulateTunnelMemoryOveruse,
             .simulateConnectionInterruption,
             .getDataVolume,
             .cancelSnooze: break

        }

        var data = Data([self.name.rawValue])
        encoder(&data)
        return data
    }

}

public struct ExtensionMessageString: RawRepresentable {

    private static let preferredStringEncoding = String.Encoding.utf16

    public let value: String

    init(_ value: String) {
        self.value = value
    }

    public init?(rawValue data: Data) {
        guard let value = String(data: data, encoding: Self.preferredStringEncoding) else { return nil }
        self.value = value
    }

    public var rawValue: Data {
        value.data(using: Self.preferredStringEncoding)!
    }

}

public struct ExtensionMessageBool: RawRepresentable {

    public let value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    public init?(rawValue data: Data) {
        guard data.count == 1 else { return nil }

        switch data[0] {
        case 0:
            self.value = false
        case 1:
            self.value = true
        default:
            return nil
        }
    }

    public var rawValue: Data {
        Data(value ? [1] : [0])
    }

}
