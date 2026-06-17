import Combine
import Foundation

@MainActor
public final class DeferredReadingSettingsController: ObservableObject {

    @Published public private(set) var settings: DeferredReadingSettings

    private let onChange: (DeferredReadingSettings) -> Void

    public init(settings: DeferredReadingSettings,
                onChange: @escaping (DeferredReadingSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    public var quietPeriod: DeferredReadingQuietPeriod {
        settings.quietPeriod
    }

    public var reminderDate: Date {
        var components = DateComponents()
        components.hour = settings.reminderHour
        components.minute = settings.reminderMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    public func setQuietPeriod(_ quietPeriod: DeferredReadingQuietPeriod) {
        settings.quietPeriod = quietPeriod
        onChange(settings)
    }

    public func setReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        settings.reminderHour = components.hour ?? settings.reminderHour
        settings.reminderMinute = components.minute ?? settings.reminderMinute
        onChange(settings)
    }
}
