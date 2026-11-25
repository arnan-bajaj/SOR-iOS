import Foundation
import FirebaseFirestore
import GoogleSignIn

/// A meeting as Signups and Attendance see it (shiftOf in mod-shifts): the calendar event plus what
/// meetings/{id} adds (counted, multiplier, cancelled).
struct Shift: Identifiable, Hashable {
    let id: String
    let event: CalEvent?
    let title: String
    let date: String
    let start: Double
    let end: Double
    let place: String
    let online: Bool
    let allDay: Bool
    let cancelled: Bool
    let counted: Bool
    let weight: Double
    var inPerson: Bool { !online && !place.isEmpty }
    var isBoardMeeting: Bool { event?.track == "board" || title.range(of: #"board (meeting|mtg)"#, options: [.regularExpression, .caseInsensitive]) != nil }
}

struct Score {
    var score = 0.0
    var present = 0
    var partial = 0
    var unproductive = 0
    var excused = 0
    var unexcused = 0
    var counted = 0
}

/// Adult cover for a shift (coverage in mod-shifts): 2 adults, at least 1 female, in person only. It warns, never blocks.
struct Coverage {
    let label: String
    var ok: Bool { label.isEmpty }
}

extension AppModel {
    // MARK: - Shifts

    func shift(_ id: String) -> Shift? {
        let doc = meetingExtras[id]
        let cal = events.first { $0.id == id }
        guard doc != nil || cal != nil else { return nil }
        let place = doc?["place"] as? String ?? cal?.place ?? ""
        let online = (doc?["online"] as? Bool) ?? (cal.map { $0.mode == "online" } ?? false)
        let cancelled = doc?.bool("cancelled") ?? false
        let counted = (doc?["counted"] as? Bool ?? true) && !cancelled
        let weight = (doc?.num("weight")).flatMap { $0 > 0 ? $0 : nil } ?? 1
        return Shift(id: id, event: cal, title: cal?.title ?? doc?.str("title") ?? "Meeting", date: cal?.dayKey ?? doc?.str("date") ?? "",
                     start: cal?.allDay == true ? 0 : cal?.start ?? 0, end: cal?.allDay == true ? 0 : cal?.end ?? 0,
                     place: place, online: online, allDay: cal?.allDay ?? false, cancelled: cancelled, counted: counted, weight: weight)
    }

    /// Everything you could sign up for, from today on, up to `weeks` ahead (all-day events too).
    func upcomingShifts(weeks: Int) -> [Shift] {
        let today = Day.iso()
        let horizon = Day.iso(Date().addingTimeInterval(Double(weeks) * 7 * 86400))
        var ids = events.filter { $0.dayKey >= today && $0.dayKey <= horizon || ($0.allDay && $0.end > Date().timeIntervalSince1970 * 1000 && $0.dayKey <= horizon) }.map(\.id)
        // Shifts added on the website that aren't on the calendar
        for (id, d) in meetingExtras where d.str("date") >= today && d.str("date") <= horizon && !ids.contains(id) && d.str("calendarEventId").isEmpty { ids.append(id) }
        return ids.compactMap(shift).sorted { ($0.date, $0.start) < ($1.date, $1.start) }
    }

    func signups(for id: String) -> [Signup] { signups.filter { $0.meetingId == id } }
    func amGoing(_ id: String) -> Bool { signups.contains { $0.meetingId == id && $0.uid == uid } }

    func coverage(_ sh: Shift, _ list: [Signup]) -> Coverage {
        guard sh.inPerson else { return Coverage(label: "") }
        let adults = list.filter(\.isAdult)
        let short = max(0, 2 - adults.count)
        let noFemale = !adults.contains { $0.femaleAdult }
        if short > 0 && noFemale { return Coverage(label: short > 1 ? "Needs \(short) adults, one female" : "Needs 1 more adult, female") }
        if short > 0 { return Coverage(label: "Needs \(short) more adult\(short > 1 ? "s" : "")") }
        if noFemale { return Coverage(label: "Needs a female adult") }
        return Coverage(label: "")
    }

    /// Who you are for signups (me() in mod-shifts).
    var signupKind: String {
        let t = profile?.memberType ?? ""
        if ["parent", "mentor"].contains(t) { return t }
        if ["student", "lead", "board"].contains(t) { return "student" }
        return canEdit ? "student" : "parent"
    }
    /// Students sign up in Slack; parents and mentors sign up here.
    var signsUpInApp: Bool { signupKind != "student" }

    /// The same document the website's toggleSignup writes.
    func toggleSignup(_ sh: Shift) async {
        let id = "\(sh.id)__\(uid)"
        do {
            if amGoing(sh.id) {
                if demo { signups.removeAll { $0.id == id }; return }
                try await db.document("signups/\(id)").delete()
            } else {
                let adult = signupKind != "student"
                let data: Doc = [
                    "meetingId": sh.id, "uid": uid, "name": profile?.name ?? authName, "kind": signupKind,
                    "femaleAdult": adult && (myFemale ?? false), "leader": false,
                    "title": sh.title, "date": sh.date, "start": sh.start, "end": sh.end, "place": sh.place,
                    "online": sh.online, "inPerson": sh.inPerson, "seasonId": currentSeason.id, "at": nowMs, "by": uid,
                ]
                if demo { signups.append(Signup(id: id, data)); return }
                try await db.document("signups/\(id)").setData(data)
            }
        } catch { toast = Self.friendly(error) }
    }

    /// Leads take someone off a shift.
    func removeSignup(_ s: Signup) {
        if demo { signups.removeAll { $0.id == s.id }; return }
        db.document("signups/\(s.id)").delete { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } else { self?.toast = "Took \(s.name) off this shift" } }
        }
    }

    // MARK: - Your attendance

    /// Your marks in the open season, newest first, without Board meetings (they take no attendance).
    var mySeasonMarks: [Mark] {
        let from = seasonFrom, to = currentSeason.end
        return myMarks.filter { $0.date >= from && $0.date <= to }
            .filter { m in !(shift(m.meetingId)?.isBoardMeeting ?? (m.title.range(of: #"board (meeting|mtg)"#, options: [.regularExpression, .caseInsensitive]) != nil)) }
            .sorted { $0.date > $1.date }
    }

    /// scoreOf in mod-shifts: TRUNC(online/3 + complete, 2). Present 1, Partial 0.5, only counted shifts score, multiplier applies.
    var myScore: Score {
        var out = Score()
        var online = 0.0, complete = 0.0
        for m in mySeasonMarks {
            guard let st = MarkStatus(rawValue: m.status) else { continue }
            if st == .excused { out.excused += 1 }
            if st == .unexcused { out.unexcused += 1 }
            let sh = shift(m.meetingId)
            guard sh?.counted ?? true else { continue }
            out.counted += 1
            if st == .partial { out.partial += 1 }
            if st == .unproductive { out.unproductive += 1 }
            if st == .present { out.present += 1 }
            let worth = st.value * (sh?.weight ?? 1)
            if sh?.online ?? m.online { online += worth } else { complete += worth }
        }
        out.score = (((online / 3) + complete) * 100).rounded(.towardZero) / 100
        return out
    }

    // MARK: - Action items

    func items(track: Track) -> [ActionItem] {
        let sid = currentSeason.id
        return actionItems.filter { a in
            a.seasonId == sid && (a.track == track.rawValue || (a.track.isEmpty && events.first(where: { $0.id == a.meetingId })?.track == track.rawValue))
        }
    }
    var boardRoomItems: [ActionItem] { privateActionItems.filter { $0.seasonId == currentSeason.id } }
    var myOpenActionItems: [ActionItem] {
        actionItems.filter { $0.seasonId == currentSeason.id && !$0.done && $0.ownerUids.contains(uid) }.sorted { $0.dueDate.isEmpty ? false : $1.dueDate.isEmpty ? true : $0.dueDate < $1.dueDate }
    }
    func canChange(_ a: ActionItem) -> Bool { a.confidential ? isBoardMember : canEdit }
    func canRemove(_ a: ActionItem) -> Bool { a.confidential ? isBoardMember : (isLead || (canEdit && a.createdBy == uid)) }

    func setDone(_ a: ActionItem, _ done: Bool) {
        patch(a, ["done": done])
    }

    func patch(_ a: ActionItem, _ p: Doc) {
        if demo {
            if let i = actionItems.firstIndex(where: { $0.id == a.id }) {
                var d: Doc = ["text": a.text, "ownerUids": a.ownerUids, "dueDate": a.dueDate, "done": a.done, "track": a.track, "assignedOn": a.assignedOn, "createdBy": a.createdBy, "seasonId": a.seasonId]
                d.merge(p) { _, n in n }
                actionItems[i] = ActionItem(id: a.id, d)
            }
            return
        }
        db.document(a.path).updateData(p) { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } }
        }
    }

    func deleteItem(_ a: ActionItem) {
        if demo { actionItems.removeAll { $0.id == a.id }; return }
        db.document(a.path).delete { [weak self] err in
            MainActor.assumeIsolated { self?.toast = err.map(Self.friendly) ?? "Deleted “\(a.text)”" }
        }
    }

    /// Assigned at the nearest meeting of that kind today, like the Action Items page does.
    func addActionItem(text: String, track: Track, owners: [String], dueDate: String, confidential: Bool) async throws {
        let today = Day.iso()
        let now = Date().timeIntervalSince1970 * 1000
        let ev = events.filter { $0.dayKey == today && $0.track == track.rawValue }.min { abs($0.start - now) < abs($1.start - now) }
        var data: Doc = [
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines), "ownerUids": owners.isEmpty ? [uid] : owners,
            "dueDate": dueDate, "done": false, "track": track.rawValue, "meetingId": ev?.id ?? "", "assignedOn": today,
            "promotedTaskId": "", "createdBy": uid, "createdAt": nowMs, "seasonId": currentSeason.id, "reminders": [90],
        ]
        if confidential { data["confidential"] = true }
        if demo { actionItems.append(ActionItem(id: UUID().uuidString, data)); return }
        try await db.collection(confidential ? "privateActionItems" : "actionItems").addDocument(data: data)
    }

    // MARK: - Hangar agendas

    var seasonAgendas: [Agenda] {
        let from = seasonFrom, to = currentSeason.end
        return agendas.filter { !$0.removed && $0.date >= from && $0.date <= to }.sorted { $0.date > $1.date }
    }

    // MARK: - Team (admins approve people, Team page)

    var pendingPeople: [Person] { users.filter { $0.role == .pending && $0.onboardedAt > 0 } }

    /// approveRole in mod-views: what their member type is offered on approval.
    func approveRole(_ p: Person) -> Role {
        switch p.memberType {
        case "lead", "mentor": .lead
        case "parent": .viewer
        default: .member
        }
    }

    func setRole(_ p: Person, _ role: Role) {
        if demo { if let i = users.firstIndex(of: p) { users[i].role = role }; return }
        db.document("users/\(p.id)").updateData(["role": role.rawValue]) { [weak self] err in
            MainActor.assumeIsolated { self?.toast = err.map(Self.friendly) ?? "\(p.firstName) is in as \(role.label.lowercased())" }
        }
    }

    func decline(_ p: Person) {
        if demo { users.removeAll { $0.id == p.id }; return }
        db.document("users/\(p.id)").delete { [weak self] err in
            MainActor.assumeIsolated { self?.toast = err.map(Self.friendly) ?? "Declined \(p.firstName)" }
        }
    }

    // MARK: - Archive

    var archivedTasks: [TaskItem] {
        allTasks.filter { $0.archived && $0.seasonId == currentSeason.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Website pages inside the app

    /// A fresh Google token for the website's sign-in (window.sorAppToken), so pages open already signed in.
    func googleTokenForWeb() async -> (idToken: String, accessToken: String)? {
        if demo { return nil }
        do {
            var user = GIDSignIn.sharedInstance.currentUser
            if user == nil { user = try await GIDSignIn.sharedInstance.restorePreviousSignIn() }
            guard let fresh = try await user?.refreshTokensIfNeeded(), let id = fresh.idToken?.tokenString else { return nil }
            return (id, fresh.accessToken.tokenString)
        } catch {
            return nil
        }
    }
}
