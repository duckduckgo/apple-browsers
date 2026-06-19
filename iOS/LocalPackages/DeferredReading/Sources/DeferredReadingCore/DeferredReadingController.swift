import Combine
import Foundation
import Persistence
import UserNotifications

@MainActor
public final class DeferredReadingController: ObservableObject {

    public enum Constants {
        public static let notificationIdentifier = "com.duckduckgo.deferredReading.reminder"
        public static let debugNotificationIdentifier = "com.duckduckgo.deferredReading.reminder.debug"
        public static let notificationCategoryIdentifier = "com.duckduckgo.deferredReading.category"
    }

    private enum StorageKey {
        static let items = "deferred-reading.items"
        static let settings = "deferred-reading.settings"
        static let pausedDate = "deferred-reading.paused-date"
    }

    @Published public private(set) var items: [DeferredReadingItem] = []
    @Published public private(set) var unreadCount: Int = 0
    @Published public private(set) var settingsController: DeferredReadingSettingsController

    private let keyValueStore: ThrowingKeyValueStoring
    private let notificationCenter: UNUserNotificationCenter
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let isFeatureEnabled: () -> Bool
    private var pausedDate: Date?

    public init(keyValueStore: ThrowingKeyValueStoring,
                notificationCenter: UNUserNotificationCenter = .current(),
                calendar: Calendar = .current,
                nowProvider: @escaping () -> Date = Date.init,
                isFeatureEnabled: @escaping () -> Bool = { true }) {
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.isFeatureEnabled = isFeatureEnabled

        let initialSettings = Self.loadSettings(from: keyValueStore)
        settingsController = DeferredReadingSettingsController(settings: initialSettings) { _ in }

        settingsController = DeferredReadingSettingsController(settings: initialSettings) { [weak self] newSettings in
            self?.storeSettings(newSettings)
            self?.rescheduleNotification()
        }

        items = Self.loadItems(from: keyValueStore)
        pausedDate = Self.loadPausedDate(from: keyValueStore)
        updateUnreadCount()
        registerNotificationCategory()
        rescheduleNotification()
    }

    public var isEnabled: Bool {
        isFeatureEnabled()
    }

    public var unreadItems: [DeferredReadingItem] {
        items.filter { !$0.isRead }
            .sorted { $0.addedAt > $1.addedAt }
    }

    public var readItems: [DeferredReadingItem] {
        items.filter(\.isRead)
            .sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
    }

    public func shouldPromptForExternalURLNow(date: Date = Date()) -> Bool {
        guard isFeatureEnabled() else { return false }
        guard !isPromptPaused(on: date) else { return false }
        return settingsController.quietPeriod.contains(date, calendar: calendar)
    }

    public func pausePromptsForToday(date: Date = Date()) {
        pausedDate = date
        persistPausedDate()
    }

    public func resetPromptPause() {
        pausedDate = nil
        persistPausedDate()
    }

    public func isPromptPausedToday(date: Date = Date()) -> Bool {
        isPromptPaused(on: date)
    }

    public func deferURL(_ url: URL, title: String? = nil, date: Date = Date()) {
        guard isFeatureEnabled() else { return }
        let item = DeferredReadingItem(
            urlString: url.absoluteString,
            title: title,
            addedAt: date
        )
        items.insert(item, at: 0)
        persistItems()
        updateUnreadCount()
        rescheduleNotification()
    }

    public func markAsRead(itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        guard items[index].readAt == nil else { return }
        items[index].readAt = nowProvider()
        persistItems()
        updateUnreadCount()
        rescheduleNotification()
    }

    public func open(_ item: DeferredReadingItem) -> URL? {
        markAsRead(itemID: item.id)
        return item.url
    }

    public func delete(itemID: UUID) {
        items.removeAll { $0.id == itemID }
        persistItems()
        updateUnreadCount()
        rescheduleNotification()
    }

    public func clearRead() {
        items.removeAll { $0.isRead }
        persistItems()
        updateUnreadCount()
        rescheduleNotification()
    }

    public func clearAll() {
        items = []
        persistItems()
        updateUnreadCount()
        rescheduleNotification()
    }

    public func addedActionMessage(date: Date = Date()) -> String {
        "Added, we'll remind you \(reminderWindowDescription(from: date))."
    }

    public func nextScheduledReminderDate() -> Date? {
        guard isFeatureEnabled(),
              settingsController.quietPeriod != .never,
              unreadCount > 0 else {
            return nil
        }

        return nextReminderDate()
    }

    public func scheduleDebugReminderNotificationInOneMinute(now: Date = Date()) {
        Task {
            let settings = await notificationSettings()
            var status = settings.authorizationStatus

            if status == .notDetermined {
                _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
                status = await notificationSettings().authorizationStatus
            }

            guard status == .authorized || status == .provisional || status == .ephemeral else {
                return
            }

            let triggerDate = now.addingTimeInterval(60)
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let content = UNMutableNotificationContent()
            let count = max(unreadCount, 1)
            content.title = "Deferred reading reminder"
            content.body = reminderBody(unreadCount: count)
            content.categoryIdentifier = Constants.notificationCategoryIdentifier

            let request = UNNotificationRequest(
                identifier: Constants.debugNotificationIdentifier,
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }
    }

    public func debugNotificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    private func updateUnreadCount() {
        unreadCount = items.reduce(into: 0) { result, item in
            if !item.isRead {
                result += 1
            }
        }
    }

    private func persistItems() {
        do {
            let data = try JSONEncoder().encode(items)
            try keyValueStore.set(data, forKey: StorageKey.items)
        } catch {
            // Best effort persistence.
        }
    }

    private func persistPausedDate() {
        do {
            try keyValueStore.set(pausedDate?.timeIntervalSince1970, forKey: StorageKey.pausedDate)
        } catch {
            // Best effort persistence.
        }
    }

    private func storeSettings(_ settings: DeferredReadingSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            try keyValueStore.set(data, forKey: StorageKey.settings)
        } catch {
            // Best effort persistence.
        }
    }

    private func registerNotificationCategory() {
        notificationCenter.getNotificationCategories { [notificationCenter] categories in
            let category = UNNotificationCategory(
                identifier: Constants.notificationCategoryIdentifier,
                actions: [],
                intentIdentifiers: []
            )
            notificationCenter.setNotificationCategories(categories.union([category]))
        }
    }

    private func rescheduleNotification() {
        Task {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [Constants.notificationIdentifier])

            guard isFeatureEnabled(),
                  settingsController.quietPeriod != .never,
                  unreadCount > 0 else {
                return
            }

            let triggerDate = nextReminderDate()
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = "Deferred reading reminder"
            content.body = reminderBody(unreadCount: unreadCount)
            content.categoryIdentifier = Constants.notificationCategoryIdentifier

            let request = UNNotificationRequest(
                identifier: Constants.notificationIdentifier,
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }
    }

    private func nextReminderDate(from now: Date? = nil) -> Date {
        let currentDate = now ?? nowProvider()
        var components = calendar.dateComponents([.year, .month, .day], from: currentDate)
        components.hour = settingsController.settings.reminderHour
        components.minute = settingsController.settings.reminderMinute

        let todayReminder = calendar.date(from: components) ?? currentDate
        if todayReminder > currentDate {
            return todayReminder
        }

        return calendar.date(byAdding: .day, value: 1, to: todayReminder) ?? todayReminder
    }

    private func reminderWindowDescription(from now: Date) -> String {
        let reminderDate = nextReminderDate(from: now)
        let reminderHour = calendar.component(.hour, from: reminderDate)
        let dayPrefix = calendar.isDate(reminderDate, inSameDayAs: now) ? "this" : "tomorrow"

        switch reminderHour {
        case ..<12:
            return "\(dayPrefix) morning"
        case ..<18:
            return "\(dayPrefix) afternoon"
        default:
            return "\(dayPrefix) evening"
        }
    }

    private func reminderBody(unreadCount: Int) -> String {
        if unreadCount == 1 {
            return "1 URL is waiting to be read."
        }
        return "\(unreadCount) URLs are waiting to be read."
    }

    private static func loadItems(from store: ThrowingKeyValueStoring) -> [DeferredReadingItem] {
        guard let data = try? store.object(forKey: StorageKey.items) as? Data,
              let decoded = try? JSONDecoder().decode([DeferredReadingItem].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func loadSettings(from store: ThrowingKeyValueStoring) -> DeferredReadingSettings {
        guard let data = try? store.object(forKey: StorageKey.settings) as? Data,
              let decoded = try? JSONDecoder().decode(DeferredReadingSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private static func loadPausedDate(from store: ThrowingKeyValueStoring) -> Date? {
        guard let timestamp = try? store.object(forKey: StorageKey.pausedDate) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func isPromptPaused(on date: Date) -> Bool {
        guard let pausedDate else { return false }
        return calendar.isDate(pausedDate, inSameDayAs: date)
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}
