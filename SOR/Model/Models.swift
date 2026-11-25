import Foundation
import SwiftUI

/// A Firestore document as the web app writes it. Old documents miss fields, so every read has a default.
typealias Doc = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String { (self[k] as? String) ?? "" }
    func num(_ k: String) -> Double { (self[k] as? NSNumber)?.doubleValue ?? 0 }
    func bool(_ k: String) -> Bool { (self[k] as? Bool) ?? ((self[k] as? NSNumber)?.boolValue ?? false) }
    func strs(_ k: String) -> [String] { (self[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
    func docs(_ k: String) -> [Doc] { (self[k] as? [Any])?.compactMap { $0 as? Doc } ?? [] }
}

/// Milliseconds since 1970, the way the web app stores every time (`Date.now()`).
var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

// MARK: - People

/// The roles, lowest first (users/{uid}.role). Same order as ROLES in mod-state.
enum Role: String, CaseIterable {
    case pending, viewer, member, lead, admin
    var rank: Int { Role.allCases.firstIndex(of: self) ?? 0 }
    var label: String {
        switch self {
        case .pending: "Waiting for approval"
        case .viewer: "Viewer"
        case .member: "Member"
        case .lead: "Lead"
        case .admin: "Admin"
        }
    }
}

struct Person: Identifiable, Hashable {
    let id: String
    var name: String
    var email: String
    var photoURL: String
    var role: Role
    var memberType: String
    var subteamIds: [String]
    var onboardedAt: Double
    var slackId: String

    init(id: String, _ d: Doc) {
        self.id = id
        name = d.str("name").isEmpty ? d.str("email") : d.str("name")
        email = d.str("email")
        photoURL = d.str("photoURL")
        role = Role(rawValue: d.str("role")) ?? .pending
        memberType = d.str("memberType")
        subteamIds = d.strs("subteamIds")
        onboardedAt = d.num("onboardedAt")
        slackId = d.str("slackId")
    }

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var isStudent: Bool { !["parent", "mentor"].contains(memberType) }
    var memberTypeLabel: String {
        switch memberType {
        case "student": "Student"
        case "lead": "Lead"
        case "board": "Board"
        case "mentor": "Mentor"
        case "parent": "Parent volunteer"
        default: "Team member"
        }
    }
}

// MARK: - Boards

struct Subteam: Identifiable, Hashable {
    let id: String
    var name: String
    var color: Color
    var position: Double
    init(id: String, _ d: Doc) {
        self.id = id
        name = d.str("name")
        color = Color(hex: d.str("color")) ?? .accentColor
        position = d.num("position")
    }
}

struct BoardColumn: Identifiable, Hashable {
    let id: String
    var name: String
    var position: Double
    var subteamIds: [String]
    init(id: String, _ d: Doc) {
        self.id = id
        name = d.str("name")
        position = d.num("position")
        subteamIds = d.strs("subteamIds")
    }
}

enum Priority: String, CaseIterable, Identifiable {
    case low, med, high, critical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: "Low"
        case .med: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }
    var rank: Int { [.critical: 0, .high: 1, .med: 2, .low: 3][self] ?? 2 }
    var tint: Color {
        switch self {
        case .low: .secondary
        case .med: .blue
        case .high: .orange
        case .critical: .red
        }
    }
}

struct ChecklistItem: Hashable {
    var text: String
    var done: Bool
}

struct TaskItem: Identifiable, Hashable {
    let id: String
    var title: String
    var description: String
    var columnId: String
    var subteamId: String
    var assigneeUids: [String]
    var backupUids: [String]
    var dueDate: String // "YYYY-MM-DD" or ""
    var newDueDate: String // a second deadline, when the first slipped
    var childIds: [String] // a goal's parts
    var startDate: String
    var priority: Priority
    var checklist: [ChecklistItem]
    var blockedBy: [String]
    var isGoal: Bool
    var flagged: Bool
    var archived: Bool
    var seasonId: String
    var position: Double
    var createdBy: String
    var createdAt: Double
    var updatedAt: Double
    var commentCount: Int

    init(id: String, _ d: Doc) {
        self.id = id
        title = d.str("title")
        description = d.str("description")
        columnId = d.str("columnId")
        subteamId = d.str("subteamId")
        assigneeUids = d.strs("assigneeUids")
        backupUids = d.strs("backupUids")
        dueDate = d.str("dueDate")
        newDueDate = d.str("newDueDate")
        childIds = d.strs("childIds")
        startDate = d.str("startDate")
        priority = Priority(rawValue: d.str("priority")) ?? .med
        checklist = d.docs("checklist").map { ChecklistItem(text: $0.str("text"), done: $0.bool("done")) }
        blockedBy = d.strs("blockedBy")
        isGoal = d.bool("isGoal")
        flagged = d.bool("flagged")
        archived = d.bool("archived")
        seasonId = d.str("seasonId").isEmpty ? Season.home : d.str("seasonId")
        position = d.num("position")
        createdBy = d.str("createdBy")
        createdAt = d.num("createdAt")
        updatedAt = d.num("updatedAt")
        commentCount = Int(d.num("commentCount"))
    }

    var due: Date? { Day.date(dueDate) }
    /// The deadline that counts now: the second one if there is one.
    var effectiveDue: String { newDueDate.isEmpty ? dueDate : newDueDate }
}

struct Comment: Identifiable, Hashable {
    let id: String
    var authorId: String
    var body: String
    var createdAt: Double
    init(id: String, _ d: Doc) {
        self.id = id
        authorId = d.str("authorId")
        body = d.str("body")
        createdAt = d.num("createdAt")
    }
}

// MARK: - Seasons, arrivals

struct Season: Identifiable, Hashable {
    static let home = "offseason-2026"
    let id: String
    var name: String
    var start: String
    var end: String
    var archived: Bool
    init(id: String, _ d: Doc) {
        self.id = id
        name = d.str("name")
        start = d.str("start")
        end = d.str("end")
        archived = d.bool("archived")
    }
    init(id: String, name: String, start: String, end: String) {
        self.id = id; self.name = name; self.start = start; self.end = end; archived = false
    }
    static let defaults = [Season(id: home, name: "Offseason 2026", start: "2026-04-01", end: "2027-01-08")]
}

struct Arrival: Identifiable, Hashable {
    let id: String
    var uid: String
    var name: String
    var photoURL: String
    var at: Double
    init(id: String, _ d: Doc) {
        self.id = id
        uid = d.str("uid")
        name = d.str("name")
        photoURL = d.str("photoURL")
        at = d.num("at")
    }
}

// MARK: - Days

/// Local calendar days as "YYYY-MM-DD", like dayISO() in the web app.
enum Day {
    static func iso(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func date(_ iso: String) -> Date? {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    /// Whole days from today to `iso` (negative = past).
    static func until(_ iso: String) -> Int? {
        guard let d = date(iso) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day
    }
    static func pretty(_ iso: String) -> String {
        guard let d = date(iso), let n = until(iso) else { return iso }
        switch n {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return d.formatted(.dateTime.weekday(.wide))
        default: return d.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

// MARK: - Colors

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// The board's slate ramp in dark mode (page #0f1214 < card #1c2125 < sheet #22282c), system greys in light.
    static let page = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x0F / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1) : .systemGroupedBackground })
    static let card = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x1C / 255, green: 0x21 / 255, blue: 0x25 / 255, alpha: 1) : .secondarySystemGroupedBackground })
    static let sheet = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x22 / 255, green: 0x28 / 255, blue: 0x2C / 255, alpha: 1) : .systemBackground })
}

// MARK: - Meetings: signups, attendance, agendas, action items

struct Signup: Identifiable, Hashable {
    let id: String
    var meetingId: String
    var uid: String
    var name: String
    var kind: String // student | parent | mentor
    var femaleAdult: Bool
    var leader: Bool
    var rosterId: String
    init(id: String, _ d: Doc) {
        self.id = id
        rosterId = d.str("rosterId")
        meetingId = d.str("meetingId")
        uid = d.str("uid")
        name = d.str("name")
        kind = d.str("kind")
        femaleAdult = d.bool("femaleAdult")
        leader = d.bool("leader")
    }
    var isAdult: Bool { kind == "parent" || kind == "mentor" }
}

/// An attendance mark (attendance/{meetingId__who}). No document means Not present.
struct Mark: Identifiable, Hashable {
    let id: String
    var meetingId: String
    var date: String
    var title: String
    var online: Bool
    var status: String
    var uid: String
    var rosterId: String
    var name: String
    var kind: String
    init(id: String, _ d: Doc) {
        self.id = id
        uid = d.str("uid"); rosterId = d.str("rosterId"); name = d.str("name"); kind = d.str("kind")
        meetingId = d.str("meetingId")
        date = d.str("date")
        title = d.str("title")
        online = d.bool("online")
        status = d.str("status")
    }
}

/// STATUSES in mod-shifts, in the sheet's order.
enum MarkStatus: String, CaseIterable {
    case present, partial, unproductive, excused, unexcused
    var label: String {
        switch self {
        case .present: "Present"
        case .partial: "Partial"
        case .unproductive: "Unproductive"
        case .excused: "Absent excused"
        case .unexcused: "Absent unexcused"
        }
    }
    var value: Double { self == .present ? 1 : self == .partial ? 0.5 : 0 }
    var tint: Color {
        switch self {
        case .present: .green
        case .partial: .yellow
        case .unproductive: .orange
        case .excused: .blue
        case .unexcused: .red
        }
    }
}

struct Agenda: Identifiable, Hashable {
    let id: String
    var title: String
    var body: String
    var date: String
    var subteamIds: [String]
    var authorName: String
    var permalink: String
    var removed: Bool
    var taskIds: [String]
    init(id: String, _ d: Doc) {
        self.id = id
        title = d.str("title")
        body = d.str("body")
        date = d.str("date")
        subteamIds = d.strs("subteamIds")
        authorName = d.str("authorName")
        permalink = d.str("permalink")
        removed = d.bool("removed")
        taskIds = d.strs("taskIds")
    }
}

enum Track: String, CaseIterable, Identifiable {
    case board, build, ops
    var id: String { rawValue }
    var label: String { self == .board ? "Board" : self == .build ? "Build Committee" : "Operations" }
}

struct ActionItem: Identifiable, Hashable {
    let id: String
    var text: String
    var ownerUids: [String]
    var dueDate: String
    var done: Bool
    var track: String
    var meetingId: String
    var assignedOn: String
    var createdBy: String
    var createdAt: Double
    var seasonId: String
    var confidential: Bool
    init(id: String, _ d: Doc, confidential: Bool = false) {
        self.id = id
        text = d.str("text")
        ownerUids = d.strs("ownerUids").isEmpty ? (d.str("ownerUid").isEmpty ? [] : [d.str("ownerUid")]) : d.strs("ownerUids")
        dueDate = d.str("dueDate")
        done = d.bool("done")
        track = d.str("track")
        meetingId = d.str("meetingId")
        assignedOn = d.str("assignedOn")
        createdBy = d.str("createdBy")
        createdAt = d.num("createdAt")
        seasonId = d.str("seasonId").isEmpty ? Season.home : d.str("seasonId")
        self.confidential = confidential || d.bool("confidential")
    }
    var path: String { "\(confidential ? "privateActionItems" : "actionItems")/\(id)" }
    /// assignedDay in mod-views: assignedOn, else the day it was added.
    var day: String { assignedOn.isEmpty ? Day.iso(Date(timeIntervalSince1970: createdAt / 1000)) : assignedOn }
}

// MARK: - Board Room and agenda documents

struct ChannelMessage: Identifiable, Hashable {
    let id: String
    var text: String
    var authorId: String
    var authorName: String
    var createdAt: Double
    var kind: String // "" or "season" (the line a season switch leaves)
    init(id: String, _ d: Doc) {
        self.id = id
        text = d.str("text"); authorId = d.str("authorId"); authorName = d.str("authorName"); createdAt = d.num("createdAt"); kind = d.str("kind")
    }
}

/// A Board, Build Committee or Operations agenda written on the website (boardAgendas / meetingAgendas).
struct AgendaDoc: Identifiable, Hashable {
    struct Item: Hashable { var topic, points, who, urgency: String; var minutes: Int }
    let id: String
    var track: String
    var date: String
    var startTime: String
    var recording: String
    var attended: [String]
    var purpose, takeaways, topics, nextSteps: String
    var items: [Item]
    init(id: String, _ d: Doc) {
        self.id = id
        track = d.str("track"); date = d.str("date"); startTime = d.str("startTime"); recording = d.str("recording")
        attended = d.strs("attended")
        purpose = d.str("purpose"); takeaways = d.str("takeaways"); topics = d.str("topics"); nextSteps = d.str("nextSteps")
        items = d.docs("items").map { Item(topic: $0.str("topic"), points: $0.str("points"), who: $0.str("who"), urgency: $0.str("urgency"), minutes: Int($0.num("minutes"))) }
    }
    var totalMinutes: Int { items.map(\.minutes).reduce(0, +) }
}

/// A Google Doc agenda made by /agenda in Slack (meetingDocs / boardMeetingDocs).
struct GoogleDoc: Identifiable, Hashable {
    let id: String
    var track: String
    var url: String
    var title: String
    var date: String
    init(id: String, _ d: Doc) {
        self.id = id
        track = d.str("track"); url = d.str("url"); title = d.str("title"); date = d.str("date")
    }
}

/// One message to the helper (assistantLogs), for its reviewers.
struct HelperLog: Identifiable, Hashable {
    let id: String
    var name, said, reply, role, day, error: String
    var at: Double
    var status: Int
    var calls: [String]
    init(id: String, _ d: Doc) {
        self.id = id
        name = d.str("name"); said = d.str("said"); reply = d.str("reply"); role = d.str("role"); day = d.str("day"); error = d.str("error")
        at = d.num("at"); status = Int(d.num("status"))
        calls = d.docs("calls").map { $0.str("name").replacingOccurrences(of: "_", with: " ") }
    }
}

/// Someone on the team's roster (roster/{id}): students, parents and mentors, with or without a board account.
struct RosterPerson: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: String // student | parent | mentor
    var uid: String
    var aliases: [String]
    var active: Bool
    var female: Bool
    init(id: String, _ d: Doc) {
        self.id = id
        name = d.str("name"); kind = d.str("kind"); uid = d.str("uid"); aliases = d.strs("aliases")
        active = (d["active"] as? Bool) ?? true
        female = d.bool("female")
    }
}
