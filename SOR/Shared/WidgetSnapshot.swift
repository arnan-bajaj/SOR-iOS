import Foundation
import Security

/// What the Home Screen widget shows. The app writes it whenever its data changes; the widget only reads it (widgets
/// can't sign in or reach Firestore themselves). It's shared through a keychain access group, not an App Group: the
/// team's Individual Apple account can't register App Groups from this Mac (only the account holder can, on the website).
struct WidgetSnapshot: Codable {
    struct Meeting: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var place: String
        var allDay: Bool
        var going: Bool
    }
    var meetings: [Meeting] = []
    var competition: String = ""
    var competitionDate: Date?
    var openTasks: Int = 0
    var dueSoon: Int = 0
    var updated = Date()

    /// "<team>.org.systemoverload.team.shared", from Info.plist (SORKeychainGroup). Test installs have no group,
    /// so their widget just shows a sample.
    static var accessGroup: String? {
        let g = Bundle.main.object(forInfoDictionaryKey: "SORKeychainGroup") as? String ?? ""
        return g.isEmpty || g.hasPrefix("$(") || g.hasPrefix(".") ? nil : g
    }
    private static func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "sor.widget", kSecAttrAccount as String: "snapshot"]
        if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    static func load() -> WidgetSnapshot? {
        var q = query()
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let q = Self.query()
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(q.merging(attrs) { a, _ in a } as CFDictionary, nil)
        }
    }

    static func clear() { SecItemDelete(query() as CFDictionary) }

    static let sample = WidgetSnapshot(
        meetings: [Meeting(title: "Hangar Build Session", start: Date().addingTimeInterval(3 * 3600), end: Date().addingTimeInterval(6 * 3600), place: "The hangar", allDay: false, going: true)],
        competition: "Valley Robotics Showdown", competitionDate: Date().addingTimeInterval(23 * 86400), openTasks: 4, dueSoon: 1)
}
