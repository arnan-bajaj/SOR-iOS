import Foundation
import UIKit
import UserNotifications
import WidgetKit
import FirebaseFirestore
import FirebaseMessaging

/// Somewhere the app was asked to go: a universal link (team.systemoverload.org/…), a tapped notification, or a QR code.
enum AppLink: Identifiable, Hashable {
    case task(String)
    case action(String)
    case meeting(String)
    case web(String)
    var id: String {
        switch self {
        case .task(let x): "task/\(x)"
        case .action(let x): "action/\(x)"
        case .meeting(let x): "meeting/\(x)"
        case .web(let x): "web/\(x)"
        }
    }
}

/// The kinds of notification someone can turn off (users/{uid}.push.<kind> = false). The bot reads the same names
/// (slack-bot/lib/push.mjs).
enum PushKind: String, CaseIterable, Identifiable {
    case tasks, comments, actions, reminders, meetings, team
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tasks: "Put on a task"
        case .comments: "Comments on your tasks"
        case .actions: "Action items for you"
        case .reminders: "Due-date reminders"
        case .meetings: "Meetings you signed up for"
        case .team: "Approvals"
        }
    }
    var hint: String {
        switch self {
        case .tasks: "When someone makes you an owner of a task."
        case .comments: "When someone comments on a task you own."
        case .actions: "When you're given an action item at a meeting."
        case .reminders: "Along the way to a due date, and the morning after it's missed."
        case .meetings: "An hour before a meeting you signed up for."
        case .team: "You're approved, or (for admins) someone is waiting to be."
        }
    }
}

extension AppModel {
    // MARK: - Push notifications

    /// Asks once, after sign-in. The token is saved to pushTokens/{token}, which only the bot can read.
    func setUpPush() {
        guard !demo else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .notDetermined:
                    let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                    if ok { UIApplication.shared.registerForRemoteNotifications() }
                case .authorized, .provisional, .ephemeral:
                    UIApplication.shared.registerForRemoteNotifications()
                default: break
                }
                self.pushAllowed = settings.authorizationStatus != .denied
            }
        }
    }

    /// Messaging hands over a token (and a new one now and then).
    func savePushToken(_ token: String) {
        guard !demo, !uid.isEmpty, canRead else { pendingPushToken = token; return }
        pushToken = token
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        db.document("pushTokens/\(token)").setData(["uid": uid, "platform": "ios", "updatedAt": nowMs, "app": version]) { err in
            if let err { print("push token:", err.localizedDescription) } // the rules may not be published yet
        }
    }

    /// Signing out: this phone stops getting your notifications.
    func forgetPushToken() async {
        guard let t = pushToken, !demo else { return }
        try? await db.document("pushTokens/\(t)").delete()
        pushToken = nil
    }

    func pushOn(_ kind: PushKind) -> Bool { (profileDoc["push"] as? Doc)?[kind.rawValue] as? Bool ?? true }

    func setPush(_ kind: PushKind, _ on: Bool) {
        var map = (profileDoc["push"] as? Doc) ?? [:]
        map[kind.rawValue] = on
        profileDoc["push"] = map
        guard !demo else { return }
        db.document("users/\(uid)").updateData(["push.\(kind.rawValue)": on]) { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } }
        }
    }

    // MARK: - Links

    /// team.systemoverload.org/task/abc and friends → where they go in the app.
    func open(url: URL) {
        guard url.host == AppModel.site.host || url.host == "team.systemoverload.org" || url.scheme == "sor" else { return }
        open(path: url.path)
    }

    func open(path raw: String) {
        let parts = raw.split(separator: "/").map(String.init)
        guard let first = parts.first else { return }
        let arg = parts.count > 1 ? parts[1].removingPercentEncoding ?? parts[1] : ""
        switch (first, arg.isEmpty) {
        case ("task", false): openLink = .task(arg)
        case ("action", false): openLink = .action(arg)
        case ("signups", false): openLink = .meeting(arg)
        case ("checkin", false): Task { await checkIn(code: arg) }
        default: openLink = .web(parts.joined(separator: "/"))
        }
    }

    // MARK: - Checking in (mod-shifts checkInWithCode)

    /// In person, from half an hour before the start until the end, and not marked yet (openShifts in mod-shifts).
    var openShifts: [Shift] {
        let now = Date().timeIntervalSince1970 * 1000
        let marked = Set(myMarks.map(\.meetingId))
        return events.filter { !$0.allDay && $0.start - 30 * 60_000 <= now && now <= $0.end }
            .compactMap { shift($0.id) }
            .filter { !$0.online && !$0.cancelled && !$0.isBoardMeeting && !marked.contains($0.id) && $0.date >= seasonFrom }
    }

    /// The code is checked by firestore.rules in the same write as the mark, so it never reaches the phone.
    /// Two meetings can overlap, and only the code says which one you're at.
    func checkIn(code raw: String) async {
        let code = raw.filter(\.isNumber)
        guard code.count == 4 else { toast = "That isn't a check-in code."; return }
        // Opened from a QR code at launch: wait for the calendar and your marks to arrive first
        for _ in 0..<60 where !demo && !(loaded.contains("calendar") && loaded.contains("attendance")) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let shifts = openShifts
        guard !shifts.isEmpty else {
            toast = myMarks.contains(where: { m in events.contains { $0.id == m.meetingId && $0.dayKey == Day.iso() } }) ? "You're already checked in." : "No meeting is open for check-in right now."
            return
        }
        for sh in shifts {
            for status in statuses(sh) {
                if await send(sh, code: code, status: status) {
                    toast = status == "present" ? "Checked in to \(sh.title). You're on time." : "Checked in to \(sh.title) (Partial: after the first 25 minutes)."
                    return
                }
            }
        }
        toast = "That code didn't work. Check the Monitor and try again."
    }

    private func statuses(_ sh: Shift) -> [String] {
        Date().timeIntervalSince1970 * 1000 >= sh.start + 25 * 60_000 ? ["partial"] : ["present", "partial"] // the rules go by the server's clock
    }

    private func send(_ sh: Shift, code: String, status: String) async -> Bool {
        let id = "\(sh.id)__\(uid)"
        let mark: Doc = [
            "meetingId": sh.id, "seasonId": currentSeason.id, "date": sh.date, "title": sh.title, "online": sh.online,
            "uid": uid, "rosterId": "", "name": profile?.name ?? authName, "kind": signupKind, "status": status,
            "source": "self", "at": nowMs, "by": uid,
        ]
        if demo {
            guard code == "1234" else { return false }
            myMarks.append(Mark(id: id, mark))
            return true
        }
        let batch = db.batch()
        batch.setData(["uid": uid, "meetingId": sh.id, "code": code, "at": nowMs], forDocument: db.document("checkins/\(id)"))
        batch.setData(mark, forDocument: db.document("attendance/\(id)"))
        do { try await batch.commit(); return true } catch { return false }
    }

    // MARK: - Widget

    /// Writes what the Home Screen widget shows, at most once every few seconds.
    func updateWidget() {
        widgetTimer?.invalidate()
        widgetTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .ready else { return }
                let now = Date().timeIntervalSince1970 * 1000
                let upcoming = self.events.filter { $0.end > now && !$0.allDay && !self.isCancelled($0) }.prefix(4)
                let comp = self.nextCompetition
                let mine = self.myOpenTasks
                WidgetSnapshot(
                    meetings: upcoming.map { .init(title: $0.title, start: $0.startDate, end: $0.endDate, place: $0.shortPlace, allDay: $0.allDay, going: self.amGoing($0.id)) },
                    competition: comp?.title ?? "", competitionDate: comp.flatMap { Day.date($0.dayKey) },
                    openTasks: mine.count, dueSoon: mine.filter { (Day.until($0.dueDate) ?? 99) <= 2 }.count
                ).save()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
