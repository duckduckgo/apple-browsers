//
//  MockTunnelController.swift
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
import NetworkExtension
import VPN

public final class MockTunnelController: TunnelController, TunnelSessionProvider {

    public init() {}

    public var didCallStart = false
    public func start() async {
        didCallStart = true
    }

    public var didCallStop = false
    public func stop() async {
        didCallStop = true
    }

    public var calledCommand: VPNCommand?
    public func command(_ command: VPNCommand) async throws {
        calledCommand = command
    }

    public var isConnected: Bool {
        true
    }

    public func activeSession() async -> NETunnelProviderSession? {
        return nil
    }

}
