//
//  DataBrokerProtectionNotificationPixel.swift
//  DuckDuckGo
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
import Common
import PixelKit

public enum DataBrokerProtectionNotificationPixel {
    case notificationSentFirstScanComplete
    case notificationSentFirstFreemiumScanComplete
    case notificationSentFirstRemoval
    case notificationSentAllRecordsRemoved
    case notificationScheduled1WeekCheckIn
    case notificationSentGoToMarketFirstScan
}

extension DataBrokerProtectionNotificationPixel: PixelKitEvent {
    public var name: String {
        switch self {
        case .notificationSentFirstScanComplete:
            return "m_ios_dbp_notification_sent_first_scan_complete"
        case .notificationSentFirstFreemiumScanComplete:
            return "m_ios_dbp_freemium_notification_sent_first_scan_complete"
        case .notificationSentFirstRemoval:
            return "m_ios_dbp_notification_sent_first_removal"
        case .notificationSentAllRecordsRemoved:
            return "m_ios_dbp_notification_sent_all_records_removed"
        case .notificationScheduled1WeekCheckIn:
            return "m_ios_dbp_notification_scheduled_1_week_check_in"
        case .notificationSentGoToMarketFirstScan:
            return "m_ios_dbp_notification_sent_go_to_market_first_scan"
        }
    }

    public var params: [String: String]? {
        return nil
    }

    public var parameters: [String: String]? {
        return nil
    }

    public var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}

public class DataBrokerProtectionNotificationPixelHandler: EventMapping<DataBrokerProtectionNotificationPixel> {

    let pixelKit: PixelKit

    public init(pixelKit: PixelKit) {
        self.pixelKit = pixelKit

        super.init { _, _, _, _ in
        }

        self.eventMapper = { event, _, _, _ in
            self.pixelKit.fire(event)
        }
    }

    override init(mapping: @escaping EventMapping<DataBrokerProtectionNotificationPixel>.Mapping) {
        fatalError("Use init(pixelKit:)")
    }
}
