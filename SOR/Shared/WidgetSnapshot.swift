import Foundation

/// What the Home Screen widget shows. The app writes it to the shared app group whenever its data changes;
/// the widget only reads it (widgets can't sign in or reach Firestore themselves).
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

    static let group = "group.org.systemoverload.team"
    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }

    static let sample = WidgetSnapshot(
        meetings: [Meeting(title: "Hangar Build Session", start: Date().addingTimeInterval(3 * 3600), end: Date().addingTimeInterval(6 * 3600), place: "The hangar", allDay: false, going: true)],
        competition: "Valley Robotics Showdown", competitionDate: Date().addingTimeInterval(23 * 86400), openTasks: 4, dueSoon: 1)
}
