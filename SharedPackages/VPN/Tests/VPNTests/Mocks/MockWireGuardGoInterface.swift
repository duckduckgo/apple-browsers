//
//  MockWireGuardInterface.swift
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

@testable import VPN

final class MockWireGuardInterface: WireGuardGoInterface {
    var turnOnCallCount = 0
    var lastTurnOnConfig: String?
    var lastTurnOnHandle: Int32?
    var turnOnReturnHandle: Int32 = 7

    var turnOffCallCount = 0
    var lastTurnOffHandle: Int32?

    func turnOn(settings: UnsafePointer<CChar>, handle: Int32) -> Int32 {
        turnOnCallCount += 1
        lastTurnOnConfig = String(cString: settings)
        lastTurnOnHandle = handle
        return turnOnReturnHandle
    }

    func turnOff(handle: Int32) {
        turnOffCallCount += 1
        lastTurnOffHandle = handle
    }

    func getConfig(handle: Int32) -> UnsafeMutablePointer<CChar>? { nil }
    func setConfig(handle: Int32, config: String) -> Int64 { 0 }
    func bumpSockets(handle: Int32) {}
    func disableSomeRoamingForBrokenMobileSemantics(handle: Int32) {}
    func setLogger(context: UnsafeMutableRawPointer?, logFunction: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void)?) {}
}
