import Foundation
import FirebaseFirestore

/// Data for the pages that load on first use: the Board Room, agenda documents, Analytics, Helper chats and
/// Signup records. Same collections and shapes as the website.
extension AppModel {
    private func lazyListen(_ name: String, _ q: Query, _ apply: @escaping ([QueryDocumentSnapshot]) -> Void) {
        guard lazyRegs[name] == nil, !demo, phase == .ready else { return }
        lazyRegs[name] = q.addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated {
                if let err { print("listener \(name):", err.localizedDescription); return }
                apply(snap?.documents ?? [])
                self?.loaded.insert(name)
            }
        }
    }

    // MARK: Board Room

    func wantBoardRoom() {
        guard canSeeBoardRoom else { return }
        lazyListen("boardChannel", db.collection("boardChannel")) { [weak self] in
            self?.boardChannel = $0.map { ChannelMessage(id: $0.documentID, $0.data()) }.sorted { $0.createdAt < $1.createdAt }
        }
        lazyListen("boardAgendas", db.collection("boardAgendas")) { [weak self] in
            self?.boardAgendaDocs = $0.map { AgendaDoc(id: $0.documentID, $0.data()) }.sorted { $0.date > $1.date }
        }
        lazyListen("boardMeetingDocs", db.collection("boardMeetingDocs")) { [weak self] in
            self?.boardGoogleDocs = $0.map { GoogleDoc(id: $0.documentID, $0.data()) }.sorted { $0.date > $1.date }
        }
    }

    /// Only the Board posts; lead mentors read.
    func postToBoard(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, isBoardMember else { return }
        let msg: Doc = ["text": t, "authorId": uid, "authorName": profile?.name ?? "", "createdAt": nowMs]
        if demo { boardChannel.append(ChannelMessage(id: UUID().uuidString, msg)); return }
        do { try await db.collection("boardChannel").addDocument(data: msg) } catch { toast = Self.friendly(error) }
    }

    /// Moves the whole team to another season (switchTeamSeason in mod-state), with a line in the Board channel.
    func switchSeason(to season: Season) async {
        guard canSeeBoardRoom else { return }
        let at = nowMs
        let name = profile?.name ?? ""
        let batch = db.batch()
        batch.setData(["activeId": season.id, "since": Day.iso(), "by": uid, "byName": name, "at": at], forDocument: db.document("settings/season"))
        batch.setData(["kind": "season", "seasonId": season.id, "seasonName": season.name, "text": "\(name) switched the team to \(season.name)",
                       "authorId": uid, "authorName": name, "createdAt": at], forDocument: db.collection("boardChannel").document())
        do { try await batch.commit(); toast = "The team is on \(season.name)" } catch { toast = Self.friendly(error) }
    }

    // MARK: Agenda documents (Action Items)

    func wantAgendaDocs() {
        lazyListen("meetingAgendas", db.collection("meetingAgendas")) { [weak self] in
            self?.agendaDocs = $0.map { AgendaDoc(id: $0.documentID, $0.data()) }.sorted { $0.date > $1.date }
        }
        lazyListen("meetingDocs", db.collection("meetingDocs")) { [weak self] in
            self?.googleDocs = $0.map { GoogleDoc(id: $0.documentID, $0.data()) }.sorted { $0.date > $1.date }
        }
        if canSeeBoardRoom { wantBoardRoom() }
    }

    func docs(for track: Track) -> (agendas: [AgendaDoc], google: [GoogleDoc]) {
        if track == .board { return (boardAgendaDocs, boardGoogleDocs) }
        return (agendaDocs.filter { $0.track == track.rawValue }, googleDocs.filter { $0.track == track.rawValue })
    }

    // MARK: The team's attendance (Analytics)

    func wantTeamAttendance() {
        lazyListen("teamAttendance", db.collection("attendance").whereField("date", isGreaterThanOrEqualTo: seasonFrom)) { [weak self] in
            self?.teamMarks = $0.map { Mark(id: $0.documentID, $0.data()) }
        }
    }

    struct Standing: Identifiable { let id: String; let name: String; let uid: String; let score: Score; var place = 0 }

    /// leaderboard() in mod-shifts: students only (not adults, not the Board), counted shifts up to today that someone
    /// was marked at. Ties share a place.
    var leaderboard: [Standing] {
        let today = Day.iso(), end = currentSeason.end, from = seasonFrom
        let marks = teamMarks.filter { $0.date >= from && $0.date <= end && $0.date <= today && !["parent", "mentor"].contains($0.kind) }
        var people: [String: (name: String, uid: String, marks: [Mark])] = [:]
        for m in marks {
            let key = m.uid.isEmpty ? "r-\(m.rosterId)" : m.uid
            guard key != "r-" else { continue }
            people[key, default: (m.name, m.uid, [])].marks.append(m)
        }
        let board = Set(users.filter { $0.memberType == "board" }.map(\.id))
        var rows = people.filter { !board.contains($0.value.uid) }.map { key, v in
            Standing(id: key, name: person(v.uid)?.name ?? v.name, uid: v.uid, score: score(of: v.marks))
        }
        rows.sort { $0.score.score != $1.score.score ? $0.score.score > $1.score.score : $0.score.unexcused != $1.score.unexcused ? $0.score.unexcused < $1.score.unexcused : $0.name < $1.name }
        var place = 0
        for i in rows.indices { place = i > 0 && rows[i - 1].score.score == rows[i].score.score ? place : i + 1; rows[i].place = place }
        return rows
    }

    func score(of marks: [Mark]) -> Score {
        var out = Score()
        var online = 0.0, complete = 0.0
        for m in marks {
            guard let st = MarkStatus(rawValue: m.status) else { continue }
            let sh = shift(m.meetingId)
            if sh?.isBoardMeeting == true { continue }
            if st == .excused { out.excused += 1 }
            if st == .unexcused { out.unexcused += 1 }
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

    // MARK: Helper chats (reviewers) and signup records (leads)

    func checkHelperReviewer() async {
        guard !demo, let d = try? await db.document("assistantAccess/reviewers").getDocument().data() else { return }
        isHelperReviewer = d.strs("uids").contains(uid)
    }

    func helperLogs(limit: Int) async throws -> [HelperLog] {
        let snap = try await db.collection("assistantLogs").order(by: "at", descending: true).limit(to: limit).getDocuments()
        return snap.documents.map { HelperLog(id: $0.documentID, $0.data()) }
    }

    /// The bot's text log of #meeting-signups, oldest first. Names students, so only leads can read it.
    func signupLogText() async throws -> String? {
        let docs = try await db.collection("signupLog").getDocuments().documents.sorted { $0.documentID < $1.documentID }
        guard !docs.isEmpty else { return nil }
        let head = "SOR Team Board: #meeting-signups log\nDownloaded \(Date().formatted()) by \(profile?.name ?? ""). \(docs.count) entries, oldest first.\n"
        return head + "\n" + docs.map { $0.data().str("text") }.joined(separator: "\n\n") + "\n"
    }

    /// The newest weekly export of every signup and attendance mark.
    func latestExportText() async throws -> (day: String, text: String)? {
        let all = try await db.collection("signupExports").getDocuments().documents
        guard let latest = all.max(by: { $0.data().str("day") < $1.data().str("day") }) else { return nil }
        let day = latest.data().str("day").isEmpty ? latest.documentID : latest.data().str("day")
        let parts = try await db.collection("signupExports/\(day)/parts").getDocuments().documents
            .sorted { ($0.data()["i"] as? Int ?? Int($0.documentID) ?? 0) < ($1.data()["i"] as? Int ?? Int($1.documentID) ?? 0) }
        return (day, parts.map { $0.data().str("text") }.joined(separator: "\n"))
    }

    // MARK: Timeline

    struct Goal: Identifiable {
        let task: TaskItem
        let parts: [TaskItem]
        let late: Bool
        var id: String { task.id }
        var done: Int
    }

    /// The Pinboard's big notes: team goals, plus subteam priorities that aren't part of a team goal, in date order.
    var pinboardGoals: [Goal] {
        let live = tasks
        let goals = live.filter(\.isGoal)
        let inTeamGoal = Set(goals.filter { $0.subteamId == "goals" }.flatMap(\.childIds))
        let fortnight = Date().addingTimeInterval(-14 * 86400).timeIntervalSince1970 * 1000
        let today = Day.iso()
        return goals
            .filter { ($0.subteamId == "goals" || !inTeamGoal.contains($0.id)) && (!isDone($0) || $0.updatedAt > fortnight) }
            .sorted { ($0.dueDate.isEmpty ? "9999" : $0.dueDate, $0.position) < ($1.dueDate.isEmpty ? "9999" : $1.dueDate, $1.position) }
            .map { g in
                let parts = g.childIds.compactMap { id in live.first { $0.id == id } }
                return Goal(task: g, parts: parts, late: !isDone(g) && !g.dueDate.isEmpty && g.dueDate < today, done: parts.filter(isDone).count)
            }
    }

    /// Running late: past its date, or waiting on something unfinished that's due after it (the Schedule's forecast, simplified).
    func isLate(_ t: TaskItem) -> Bool {
        guard !isDone(t), !t.effectiveDue.isEmpty else { return false }
        if t.effectiveDue < Day.iso() { return true }
        return t.blockedBy.compactMap(task).contains { !isDone($0) && !$0.effectiveDue.isEmpty && $0.effectiveDue >= t.effectiveDue }
    }
}
