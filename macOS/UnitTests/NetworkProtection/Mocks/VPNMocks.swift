//
//  VPNMocks.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import VPN
import NetworkProtectionUI
@testable import DuckDuckGo_Privacy_Browser

final class MockVPNUpsellUserDefaultsPersistor: VPNUpsellUserDefaultsPersisting {
    var vpnUpsellDismissed: Bool = false
    var vpnUpsellPopoverViewed: Bool = false
    var vpnUpsellFirstPinnedDate: Date?
    var expectedUpsellTimeInterval: TimeInterval = 0
}

final class MockStatusObserver: ConnectionStatusObserver {
    var recentValue: ConnectionStatus = .disconnected
    var publisher: AnyPublisher<ConnectionStatus, Never> = Just(.disconnected).eraseToAnyPublisher()
}

final class MockConnectionErrorObserver: ConnectionErrorObserver {
    var recentValue: String?
    var publisher: AnyPublisher<String?, Never> = Just(nil).eraseToAnyPublisher()
}

final class TestPinningManager: PinningManager {
    func togglePinning(for view: PinnableView) {}
    func isPinned(_ view: PinnableView) -> Bool { false }
    func wasManuallyToggled(_ view: PinnableView) -> Bool { false }
    func pin(_ view: PinnableView) {}
    func unpin(_ view: PinnableView) {}
    func shortcutTitle(for view: PinnableView) -> String { "" }
}

final class TestNetworkProtectionStatusReporter: NetworkProtectionStatusReporter {
    private let ipcClient = IPCClientMock()

    var statusObserver: ConnectionStatusObserver { ipcClient.ipcStatusObserver }
    var serverInfoObserver: ConnectionServerInfoObserver { ipcClient.ipcServerInfoObserver }
    var connectionErrorObserver: ConnectionErrorObserver { ipcClient.ipcConnectionErrorObserver }
    var connectivityIssuesObserver: ConnectivityIssueObserver { ipcClient.ipcConnectivityIssuesObserver }
    var controllerErrorMessageObserver: ControllerErrorMesssageObserver { ipcClient.ipcControllerErrorMessageObserver }
    var dataVolumeObserver: DataVolumeObserver { ipcClient.ipcDataVolumeObserver }
    var knownFailureObserver: KnownFailureObserver { ipcClient.ipcKnownFailureObserver }
}
