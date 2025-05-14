//
//  ConnectionTimeFormatter.swift
//  BrowserServicesKit
//
//  Created by ddg on 5/14/25.
//

import Foundation

public protocol VPNTimeFormatting {
    func string(from ti: TimeInterval) -> String
}

public final class VPNTimeFormatter: VPNTimeFormatting {

    private let formatter: DateComponentsFormatter

    public init() {
        formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
    }

    public func string(from ti: TimeInterval) -> String {
        formatter.string(from: ti) ?? "0s"
    }
}
