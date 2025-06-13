//
//  NetPPopoverManagerMock.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

#if DEBUG

import AppKit
import Combine
import Foundation
import VPN

final class NetPPopoverManagerMock: NetPPopoverManager {
    var isShown: Bool { false }
    var ipcClient: NetworkProtectionIPCClient = IPCClientMock()

    func toggle(positionedBelow view: NSView, withDelegate delegate: NSPopoverDelegate) -> NSPopover? {
        return nil
    }
    func show(positionedBelow view: NSView, withDelegate delegate: any NSPopoverDelegate) -> NSPopover {
        return NSPopover()
    }
    func close() {}
}

final class IPCClientMock: NetworkProtectionIPCClient {

    final class ConnectionStatusObserverMock: VPN.ConnectionStatusObserver {
        var publisher: AnyPublisher<VPN.ConnectionStatus, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: VPN.ConnectionStatus = .notConfigured
    }
    var ipcStatusObserver: any VPN.ConnectionStatusObserver = ConnectionStatusObserverMock()

    final class ConnectionServerInfoObserverMock: VPN.ConnectionServerInfoObserver {
        var publisher: AnyPublisher<VPN.NetworkProtectionStatusServerInfo, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: VPN.NetworkProtectionStatusServerInfo = .unknown
    }
    var ipcServerInfoObserver: any VPN.ConnectionServerInfoObserver = ConnectionServerInfoObserverMock()

    final class ConnectionErrorObserverMock: VPN.ConnectionErrorObserver {
        var publisher: AnyPublisher<String?, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: String?
    }
    var ipcConnectionErrorObserver: any VPN.ConnectionErrorObserver = ConnectionErrorObserverMock()

    final class ConnectivityIssueObserverMock: VPN.ConnectivityIssueObserver {
        var publisher: AnyPublisher<Bool, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: Bool = false
    }
    var ipcConnectivityIssuesObserver: any VPN.ConnectivityIssueObserver = ConnectivityIssueObserverMock()

    final class ControllerErrorMesssageObserverMock: VPN.ControllerErrorMesssageObserver {
        var publisher: AnyPublisher<String?, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: String?
    }
    var ipcControllerErrorMessageObserver: any VPN.ControllerErrorMesssageObserver = ControllerErrorMesssageObserverMock()

    final class DataVolumeObserverMock: VPN.DataVolumeObserver {
        var publisher: AnyPublisher<DataVolume, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: DataVolume = .init()
    }
    var ipcDataVolumeObserver: any VPN.DataVolumeObserver = DataVolumeObserverMock()

    final class KnownFailureObserverMock: VPN.KnownFailureObserver {
        var publisher: AnyPublisher<KnownFailure?, Never> = PassthroughSubject().eraseToAnyPublisher()
        var recentValue: KnownFailure?
    }
    var ipcKnownFailureObserver: any VPN.KnownFailureObserver = KnownFailureObserverMock()

    func start(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func stop(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func command(_ command: VPNCommand) async throws {
        return
    }

}

final class ConnectivityIssueObserverMock: ConnectivityIssueObserver {
    var publisher: AnyPublisher<Bool, Never> = PassthroughSubject().eraseToAnyPublisher()
    var recentValue = false
}

final class ControllerErrorMesssageObserverMock: ControllerErrorMesssageObserver {
    var publisher: AnyPublisher<String?, Never> = PassthroughSubject().eraseToAnyPublisher()
    var recentValue: String?
}

#endif
