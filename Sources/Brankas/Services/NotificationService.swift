import UserNotifications
import SwiftData

struct NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func scheduleExpiryNotifications(context: ModelContext) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let secrets = try? context.fetch(FetchDescriptor<SecretItem>())
        let accounts = try? context.fetch(FetchDescriptor<Account>())

        for secret in secrets ?? [] {
            schedule(for: secret)
        }

        for account in accounts ?? [] {
            schedule(for: account)
        }
    }

    static func cancel(for itemId: UUID) {
        let ids = [
            "expiry-7-\(itemId.uuidString)",
            "expiry-3-\(itemId.uuidString)",
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func schedule(for item: SecretItem) {
        guard let expiresAt = item.expiresAt else { return }
        scheduleNotification(
            identifierPrefix: "expiry",
            id: item.id,
            title: item.name,
            subTitle: "",
            expiresAt: expiresAt
        )
    }

    private static func schedule(for account: Account) {
        guard let expiresAt = account.expiresAt else { return }
        scheduleNotification(
            identifierPrefix: "expiry",
            id: account.id,
            title: account.service.name,
            subTitle: account.identifier,
            expiresAt: expiresAt
        )
    }

    private static func scheduleNotification(identifierPrefix: String, id: UUID, title: String, subTitle: String, expiresAt: Date) {
        for daysBefore in [7, 3] {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: expiresAt) else { continue }
            guard fireDate.timeIntervalSinceNow > -60 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Brankas"
            content.subtitle = title
            if !subTitle.isEmpty {
                content.body = "\(subTitle) — expires in \(daysBefore) days"
            } else {
                content.body = "Expires in \(daysBefore) days"
            }
            content.sound = .default

            let components = DateComponents(
                year: Calendar.current.component(.year, from: fireDate),
                month: Calendar.current.component(.month, from: fireDate),
                day: Calendar.current.component(.day, from: fireDate),
                hour: 10,
                minute: 0
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "\(identifierPrefix)-\(daysBefore)-\(id.uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request)
        }
    }
}
