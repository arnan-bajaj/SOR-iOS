import Foundation
import Observation
import FirebaseAuth

/// The helper: the website's Gemini chat (mod-assistant), in the app. The site server holds the key
/// (POST /api/assistant, site-server/lib/assistant.mjs) and checks who's asking. The app sends what it already shows
/// (open tasks, people, upcoming meetings, team-visible action items) and carries out the changes Gemini suggests,
/// but only after you tap Do it on its card. Every change is written as you, so firestore.rules decide what's allowed.
/// The function names and fields here must match TOOLS in lib/assistant.mjs (and RUN in index.html).
/// Every message is saved by the server so misuse of the team's key is visible; the chat says so.
@Observable @MainActor
final class Helper {
    struct Plan { var title: String; var head: String; var lines: [String]; var path: String? }
    enum CardState { case ask, doing, done, no, failed(String) }
    enum Item: Identifiable {
        case you(UUID, String), it(UUID, String), note(UUID, String), error(UUID, String), card(UUID)
        var id: UUID {
            switch self { case .you(let i, _), .it(let i, _), .note(let i, _), .error(let i, _), .card(let i): i }
        }
    }

    var items: [Item] = []
    var cards: [UUID: (plan: Plan, state: CardState)] = [:]
    var busy = false
    var off = ""

    @ObservationIgnored private var history: [[String: Any]] = []
    @ObservationIgnored private var decisions: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var pendingText = ""
    @ObservationIgnored private var running = false
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored var onOpen: ((String) -> Void)?

    private static let maxRounds = 5
    private var key: String { "sor-helper:\(model?.uid ?? "")" }

    // MARK: Sending

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let model else { return }
        items.append(.you(UUID(), text))
        if running { pendingText += (pendingText.isEmpty ? "" : "\n") + text; return } // answered along with the cards
        history.append(["role": "user", "parts": [["text": text]]])
        if model.demo { items.append(.it(UUID(), "The helper isn't available in the demo.")); return }
        Task { await converse() }
    }

    func decide(_ id: UUID, _ yes: Bool) {
        decisions.removeValue(forKey: id)?.resume(returning: yes)
    }

    func clear() {
        guard !running else { return }
        history = []; items = []; cards = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func converse() async {
        running = true; busy = true
        defer { running = false; busy = false; pendingText = ""; save() }
        do {
            for _ in 0..<Self.maxRounds {
                let parts = try await askServer()
                history.append(["role": "model", "parts": parts.isEmpty ? [["text": ""]] : parts])
                let words = parts.filter { $0["text"] is String && ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { items.append(.it(UUID(), words)) }
                let calls = parts.compactMap { $0["functionCall"] as? [String: Any] }
                if calls.isEmpty { break }
                var reply: [[String: Any]] = []
                for c in calls {
                    let answer = await handle(c)
                    var fr: [String: Any] = ["name": c["name"] as? String ?? "", "response": answer]
                    if let id = c["id"] { fr["id"] = id }
                    reply.append(["functionResponse": fr])
                }
                if !pendingText.isEmpty { reply.append(["text": pendingText]); pendingText = "" }
                history.append(["role": "user", "parts": reply])
                busy = true
            }
        } catch {
            items.append(.error(UUID(), error.localizedDescription))
            // Back to the last time Gemini answered in words, so no half-finished exchange is left behind
            func settled(_ c: [String: Any]) -> Bool {
                (c["role"] as? String) == "model" && !((c["parts"] as? [[String: Any]]) ?? []).contains { $0["functionCall"] != nil }
            }
            while let last = history.last, !settled(last) { history.removeLast() }
        }
    }

    private func askServer() async throws -> [[String: Any]] {
        guard let user = Auth.auth().currentUser else { throw AppError("Sign in again to use the helper.") }
        let token = try await user.getIDToken()
        var req = URLRequest(url: AppModel.site.appending(path: "api/assistant"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["contents": history, "context": context()])
        busy = true
        let (data, res) = try await URLSession.shared.data(for: req)
        let out = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if out["off"] as? Bool == true { off = out["error"] as? String ?? "The helper isn't available." }
            throw AppError(out["error"] as? String ?? "The helper couldn't answer. Try again.")
        }
        return out["parts"] as? [[String: Any]] ?? []
    }

    // MARK: What Gemini gets to see (boardContext in mod-assistant)

    private func context() -> [String: Any] {
        guard let m = model else { return [:] }
        let name = { (id: String) in m.person(id)?.name ?? "" }
        let shortNote = { (s: String, n: Int) -> String in
            let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return t.count > n ? String(t.prefix(n)) + "…" : t
        }
        func task(_ t: TaskItem) -> [String: Any] {
            var d: [String: Any] = ["id": t.id, "title": t.title, "board": t.subteamId, "column": m.columnName(t.columnId),
                                    "people": t.assigneeUids.map { "\(name($0)) (\($0))" }]
            if m.isDone(t) { d["done"] = true }
            if !t.dueDate.isEmpty { d["due"] = t.dueDate }
            if t.priority != .med { d["priority"] = t.priority.rawValue }
            if t.isGoal { d["goal"] = true }
            let blocked = t.blockedBy.compactMap { m.task($0)?.title }
            if !blocked.isEmpty { d["blockedBy"] = blocked }
            if !t.description.isEmpty { d["notes"] = shortNote(t.description, 220) }
            if t.commentCount > 0 { d["comments"] = t.commentCount }
            return d
        }
        let open = m.tasks.filter { !m.isDone($0) }.sorted { ($0.dueDate.isEmpty ? "9999" : $0.dueDate) < ($1.dueDate.isEmpty ? "9999" : $1.dueDate) }
        let done = m.tasks.filter { m.isDone($0) }.sorted { $0.updatedAt > $1.updatedAt }
        let now = Date().timeIntervalSince1970 * 1000
        let horizon = Day.iso(Date().addingTimeInterval(28 * 86400))
        let hm = { (ms: Double) in Date(timeIntervalSince1970: ms / 1000).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        let meetings: [[String: Any]] = m.events.filter { $0.end > now && $0.dayKey <= horizon }.prefix(40).map { e in
            var d: [String: Any] = ["id": e.id, "title": e.title, "day": e.dayKey, "start": e.allDay ? "all day" : hm(e.start)]
            if !e.allDay { d["end"] = hm(e.end) }
            if !e.place.isEmpty { d["place"] = e.place } else if e.mode == "online" { d["place"] = "Online" }
            if m.isCancelled(e) { d["cancelled"] = true }
            if m.amGoing(e.id) { d["youreGoing"] = true }
            return d
        }
        let items: [[String: Any]] = m.actionItems.filter { $0.seasonId == m.currentSeason.id }
            .sorted { $0.done == $1.done ? $0.assignedOn > $1.assignedOn : !$0.done }
            .prefix(120).map { a in
                var d: [String: Any] = ["id": a.id, "text": shortNote(a.text, 300), "track": a.track, "owners": a.ownerUids.map { "\(name($0)) (\($0))" }, "assignedOn": a.assignedOn]
                if !a.dueDate.isEmpty { d["due"] = a.dueDate }
                if a.done { d["done"] = true }
                return d
            }
        var ctx: [String: Any] = [
            "you": ["id": m.uid, "name": m.profile?.name ?? "", "subteams": m.profile?.subteamIds ?? [], "kind": m.profile?.memberType ?? ""],
            "onPage": "the iPhone app",
            "season": m.currentSeason.name,
            "boards": m.boards.map { ["id": $0.id, "name": $0.name] },
            "columns": m.columns.sorted { $0.position < $1.position }.map { c -> [String: Any] in
                var d: [String: Any] = ["id": c.id, "name": c.name]
                if !c.subteamIds.isEmpty { d["onlyOn"] = c.subteamIds }
                return d
            },
            "people": m.users.filter { $0.role != .pending }.map { u -> [String: Any] in
                var d: [String: Any] = ["id": u.id, "name": u.name, "canBeAssigned": u.role.rank >= Role.member.rank]
                if !u.subteamIds.isEmpty { d["subteams"] = u.subteamIds }
                if !u.memberType.isEmpty { d["kind"] = u.memberType }
                return d
            },
            "openTasks": open.prefix(260).map(task),
            "recentlyDone": done.prefix(40).map(task),
            "upcomingMeetings": meetings,
            "actionItems": items,
        ]
        if let c = m.nextCompetition { ctx["nextCompetition"] = ["title": c.title, "day": c.dayKey] }
        return ctx
    }

    // MARK: Changes it can make (RUN in mod-assistant)

    private func handle(_ call: [String: Any]) async -> [String: Any] {
        guard let m = model else { return ["ok": false] }
        let name = call["name"] as? String ?? ""
        let a = call["args"] as? [String: Any] ?? [:]
        if name == "open_page" {
            let path = a.str("path")
            guard path.range(of: #"^/[\w\-/]*$"#, options: .regularExpression) != nil else { return ["ok": false, "error": "That isn't a page on the board."] }
            items.append(.note(UUID(), "Opened \(path)"))
            onOpen?(path)
            return ["ok": true, "opened": path]
        }
        let plan: Plan
        do { plan = try self.plan(name, a, m) } catch { return ["ok": false, "error": error.localizedDescription] }
        guard m.canEdit else { return ["ok": false, "error": "This account can't make changes."] }
        let id = UUID()
        cards[id] = (plan, .ask)
        items.append(.card(id))
        busy = false
        let yes = await withCheckedContinuation { decisions[id] = $0 }
        guard yes else { cards[id]?.state = .no; return ["ok": false, "cancelled": true, "note": "The person said no. Don't do it."] }
        cards[id]?.state = .doing
        do {
            let result = try await run(name, a, m)
            cards[id]?.state = .done
            return result
        } catch {
            let msg = AppModel.friendly(error)
            cards[id]?.state = .failed(msg)
            return ["ok": false, "error": msg]
        }
    }

    private func assignable(_ ids: Any?, _ m: AppModel) -> [String] {
        let list = (ids as? [Any])?.compactMap { $0 as? String } ?? []
        var seen = Set<String>()
        return list.filter { id in (m.person(id)?.role.rank ?? 0) >= Role.member.rank && seen.insert(id).inserted }
    }
    private func okDay(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        return s.isEmpty || s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? s : nil
    }
    private func needTask(_ id: String, _ m: AppModel) throws -> TaskItem {
        guard let t = m.task(id), !t.archived else { throw AppError("I couldn't find that task.") }
        return t
    }
    private func needItem(_ id: String, _ m: AppModel) throws -> ActionItem {
        guard let i = m.actionItems.first(where: { $0.id == id }) else { throw AppError("I couldn't find that action item.") }
        return i
    }
    private func names(_ ids: [String], _ m: AppModel) -> String { ids.compactMap { m.person($0)?.name }.joined(separator: ", ") }

    private func plan(_ name: String, _ a: [String: Any], _ m: AppModel) throws -> Plan {
        switch name {
        case "create_task":
            guard let board = m.boards.first(where: { $0.id == a.str("subteamId") }) else { throw AppError("That board doesn't exist.") }
            guard !a.str("title").trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError("The task needs a title.") }
            let people = assignable(a["assigneeIds"], m)
            var lines = [board.name]
            if let d = okDay(a["dueDate"]), !d.isEmpty { lines.append("Due \(Day.pretty(d))") }
            if !people.isEmpty { lines.append(names(people, m)) }
            if let p = Priority(rawValue: a.str("priority")), p != .med { lines.append("\(p.label) priority") }
            if !a.str("description").isEmpty { lines.append(String(a.str("description").prefix(140))) }
            return Plan(title: "New task", head: a.str("title"), lines: lines)
        case "update_task":
            let t = try needTask(a.str("taskId"), m)
            var lines: [String] = []
            if !a.str("title").isEmpty && a.str("title") != t.title { lines.append("Rename to “\(a.str("title"))”") }
            if let d = okDay(a["dueDate"]), d != t.dueDate { lines.append(d.isEmpty ? "No due date" : "Due \(Day.pretty(d))") }
            if let p = Priority(rawValue: a.str("priority")), p != t.priority { lines.append("\(p.label) priority") }
            let col = a.str("columnId")
            if !col.isEmpty && col != t.columnId && m.columns.contains(where: { $0.id == col }) { lines.append("Move to \(m.columnName(col))") }
            if a["assigneeIds"] is [Any] { let p = assignable(a["assigneeIds"], m); lines.append(p.isEmpty ? "Nobody on it" : "People: \(names(p, m))") }
            if let d = a["description"] as? String, d != t.description { lines.append("New notes: \(d.prefix(120))") }
            if lines.isEmpty { throw AppError("Nothing to change on that task.") }
            return Plan(title: "Change task", head: t.title, lines: lines, path: "/task/\(t.id)")
        case "set_task_done":
            let t = try needTask(a.str("taskId"), m)
            return Plan(title: a.bool("done") ? "Mark done" : "Mark not done", head: t.title, lines: [m.subteam(t.subteamId)?.name ?? ""], path: "/task/\(t.id)")
        case "comment_on_task":
            let t = try needTask(a.str("taskId"), m)
            guard !a.str("text").trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError("The comment is empty.") }
            return Plan(title: "Comment", head: t.title, lines: ["“\(a.str("text").prefix(240))”"], path: "/task/\(t.id)")
        case "create_action_item":
            guard let track = Track(rawValue: a.str("track")) else { throw AppError("Action items go on Board, Build Committee or Operations.") }
            guard !a.str("text").trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError("The action item needs some words.") }
            let owners = assignable(a["ownerIds"], m)
            var lines = [names(owners.isEmpty ? [m.uid] : owners, m)]
            if let d = okDay(a["dueDate"]), !d.isEmpty { lines.append("Due \(Day.pretty(d))") }
            return Plan(title: "New action item · \(track.label)", head: String(a.str("text").prefix(200)), lines: lines)
        case "set_action_item_done":
            let i = try needItem(a.str("actionItemId"), m)
            return Plan(title: a.bool("done") ? "Tick off" : "Mark not done", head: i.text, lines: [Track(rawValue: i.track)?.label ?? ""], path: "/action/\(i.id)")
        default:
            throw AppError("No such function.")
        }
    }

    private func run(_ name: String, _ a: [String: Any], _ m: AppModel) async throws -> [String: Any] {
        switch name {
        case "create_task":
            let cols = m.columns(for: a.str("subteamId"))
            let col = cols.first { $0.id == a.str("columnId") }?.id
            let id = try await m.createTask(title: a.str("title"), description: a.str("description"), subteamId: a.str("subteamId"), columnId: col,
                                            assignees: assignable(a["assigneeIds"], m), dueDate: okDay(a["dueDate"]) ?? "", priority: Priority(rawValue: a.str("priority")) ?? .med)
            return ["ok": true, "taskId": id]
        case "update_task":
            let t = try needTask(a.str("taskId"), m)
            var patch: Doc = [:]
            if !a.str("title").isEmpty { patch["title"] = a.str("title").trimmingCharacters(in: .whitespaces) }
            if let d = okDay(a["dueDate"]) { patch["dueDate"] = d }
            if let p = Priority(rawValue: a.str("priority")) { patch["priority"] = p.rawValue }
            let col = a.str("columnId")
            if !col.isEmpty && col != t.columnId && m.columns.contains(where: { $0.id == col }) {
                patch["columnId"] = col
                if col == m.doneColumnId { patch["prevColumnId"] = t.columnId }
            }
            if a["assigneeIds"] is [Any] { patch["assigneeUids"] = assignable(a["assigneeIds"], m) }
            if let d = a["description"] as? String { patch["description"] = d }
            m.update(t, patch)
            return ["ok": true]
        case "set_task_done":
            let t = try needTask(a.str("taskId"), m)
            if a.bool("done") == m.isDone(t) { return ["ok": true, "note": "It was already like that."] }
            if a.bool("done") { m.update(t, ["columnId": m.doneColumnId, "prevColumnId": t.columnId]) }
            else {
                let cols = m.columns(for: t.subteamId)
                let back = cols.first { $0.id == "doing" } ?? cols.first { $0.id != m.doneColumnId }
                m.update(t, ["columnId": back?.id ?? t.columnId])
            }
            return ["ok": true]
        case "comment_on_task":
            try await m.addComment(try needTask(a.str("taskId"), m), a.str("text").trimmingCharacters(in: .whitespacesAndNewlines))
            return ["ok": true]
        case "create_action_item":
            try await m.addActionItem(text: a.str("text"), track: Track(rawValue: a.str("track")) ?? .board, owners: assignable(a["ownerIds"], m),
                                      dueDate: okDay(a["dueDate"]) ?? "", confidential: false)
            return ["ok": true]
        case "set_action_item_done":
            m.setDone(try needItem(a.str("actionItemId"), m), a.bool("done"))
            return ["ok": true]
        default:
            return ["ok": false, "error": "No such function."]
        }
    }

    // MARK: Keeping the chat between visits (this phone only)

    private func save() {
        let keep = Array(history.suffix(40))
        let words: [[String: String]] = items.suffix(60).compactMap {
            switch $0 {
            case .you(_, let t): ["k": "you", "t": t]
            case .it(_, let t): ["k": "it", "t": t]
            default: nil
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["history": keep, "view": words]) { UserDefaults.standard.set(data, forKey: key) }
    }

    func restore() {
        guard items.isEmpty, let data = UserDefaults.standard.data(forKey: key),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        history = obj["history"] as? [[String: Any]] ?? []
        items = (obj["view"] as? [[String: String]] ?? []).map { $0["k"] == "you" ? .you(UUID(), $0["t"] ?? "") : .it(UUID(), $0["t"] ?? "") }
    }
}
