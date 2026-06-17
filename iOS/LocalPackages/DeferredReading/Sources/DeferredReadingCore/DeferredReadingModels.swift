import Foundation

public enum DeferredReadingQuietPeriod: String, CaseIterable, Codable {
    case morning
    case dayTime
    case evening
    case always
    case never

    public var title: String {
        switch self {
        case .morning:
            "Morning (12am - 9am)"
        case .dayTime:
            "Day time (9am - 6pm)"
        case .evening:
            "Evening (6pm - 12am)"
        case .always:
            "Always"
        case .never:
            "Never"
        }
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .morning:
            return date.hour(in: calendar) < 9
        case .dayTime:
            let hour = date.hour(in: calendar)
            return hour >= 9 && hour < 18
        case .evening:
            return date.hour(in: calendar) >= 18
        case .always:
            return true
        case .never:
            return false
        }
    }
}

public struct DeferredReadingSettings: Equatable, Codable {
    public var quietPeriod: DeferredReadingQuietPeriod
    public var reminderHour: Int
    public var reminderMinute: Int

    public init(quietPeriod: DeferredReadingQuietPeriod,
                reminderHour: Int,
                reminderMinute: Int) {
        self.quietPeriod = quietPeriod
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }

    public static let `default` = DeferredReadingSettings(
        quietPeriod: .never,
        reminderHour: 18,
        reminderMinute: 0
    )
}

public struct DeferredReadingItem: Identifiable, Equatable, Codable {
    public let id: UUID
    public let urlString: String
    public let title: String?
    public let addedAt: Date
    public var readAt: Date?

    public init(id: UUID = UUID(),
                urlString: String,
                title: String?,
                addedAt: Date,
                readAt: Date? = nil) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.addedAt = addedAt
        self.readAt = readAt
    }

    public var isRead: Bool {
        readAt != nil
    }

    public var url: URL? {
        URL(string: urlString)
    }
}

private extension Date {
    func hour(in calendar: Calendar) -> Int {
        calendar.component(.hour, from: self)
    }
}
