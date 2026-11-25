import Foundation
import FirebaseFirestore

/// Something a person reported: a comment, a task photo, a Board channel message or a task. `reports/{id}`;
/// anyone approved can file one, only admins (the Board and lead mentors) read and resolve them.
struct Report: Identifiable, Hashable {
    let id: String
    var kind: String // comment | photo | message | task
    var path: String
    var taskId: String
    var authorUid: String
    var authorName: String
    var text: String
    var reason: String
    var note: String
    var reporterName: String
    var status: String // open | resolved | removed
    var createdAt: Double
    var resolvedByName: String
    init(id: String, _ d: Doc) {
        self.id = id
        kind = d.str("kind"); path = d.str("path"); taskId = d.str("taskId"); authorUid = d.str("authorUid"); authorName = d.str("authorName")
        text = d.str("text"); reason = d.str("reason"); note = d.str("note"); reporterName = d.str("reporterName")
        status = d.str("status").isEmpty ? "open" : d.str("status"); createdAt = d.num("createdAt"); resolvedByName = d.str("resolvedByName")
    }
    var isOpen: Bool { status == "open" }
    var kindLabel: String { ["comment": "Comment", "photo": "Photo", "message": "Board channel message", "task": "Task"][kind] ?? "Content" }
}

/// What the Report sheet is about.
struct ReportTarget: Identifiable, Hashable {
    var kind: String
    var path: String
    var taskId: String = ""
    var authorUid: String
    var text: String
    var id: String { path }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case offensive = "Offensive or inappropriate"
    case harassment = "Harassment or bullying"
    case privateInfo = "Shares private information"
    case spam = "Spam or off-topic"
    case other = "Something else"
    var id: String { rawValue }
}

extension AppModel {
    // MARK: Blocking: hides that person's comments, photos and Board channel messages for you, on this phone.

    private var blockedKey: String { "sor-blocked:\(uid)" }
    func loadBlocked() { blockedUids = Set(UserDefaults.standard.stringArray(forKey: blockedKey) ?? []) }
    func isBlocked(_ id: String) -> Bool { !id.isEmpty && id != uid && blockedUids.contains(id) }
    func block(_ id: String) {
        guard !id.isEmpty, id != uid else { return }
        blockedUids.insert(id)
        UserDefaults.standard.set(Array(blockedUids), forKey: blockedKey)
        toast = "Blocked \(person(id)?.firstName ?? "them"). You won't see their comments, photos or messages."
    }
    func unblock(_ id: String) {
        blockedUids.remove(id)
        UserDefaults.standard.set(Array(blockedUids), forKey: blockedKey)
    }

    // MARK: Reports

    func report(_ t: ReportTarget, reason: ReportReason, note: String) async throws {
        let data: Doc = [
            "kind": t.kind, "path": t.path, "taskId": t.taskId, "authorUid": t.authorUid,
            "authorName": person(t.authorUid)?.name ?? "", "text": String(t.text.prefix(500)),
            "reason": reason.rawValue, "note": String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            "reporterUid": uid, "reporterName": profile?.name ?? authName, "status": "open", "createdAt": nowMs,
        ]
        if demo { reports.insert(Report(id: UUID().uuidString, data), at: 0); return }
        try await db.collection("reports").addDocument(data: data)
    }

    /// Admins only: the reports list, newest first.
    func wantReports() {
        guard !demo, phase == .ready, isAdmin, lazyRegs["reports"] == nil else { return }
        lazyRegs["reports"] = db.collection("reports").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                self?.reports = (snap?.documents ?? []).map { Report(id: $0.documentID, $0.data()) }.sorted { $0.createdAt > $1.createdAt }
                self?.loaded.insert("reports")
            }
        }
    }

    var openReports: [Report] { reports.filter(\.isOpen) }

    func setReport(_ r: Report, status: String) {
        let patch: Doc = ["status": status, "resolvedBy": uid, "resolvedByName": profile?.name ?? authName, "resolvedAt": nowMs]
        if demo {
            if let i = reports.firstIndex(where: { $0.id == r.id }) { var d = r; d.status = status; d.resolvedByName = profile?.name ?? ""; reports[i] = d }
            return
        }
        db.document("reports/\(r.id)").updateData(patch) { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } }
        }
    }

    /// Whether this admin can take the reported thing down from here (the rules decide; Board channel messages only by their author).
    func canRemove(_ r: Report) -> Bool { isLead && ["comment", "photo", "task"].contains(r.kind) }

    /// Takes the reported thing down, then marks the report removed.
    func removeReported(_ r: Report) async {
        do {
            switch r.kind {
            case "comment":
                if !demo {
                    try await db.document(r.path).delete()
                    if let t = task(r.taskId), t.commentCount > 0 { try? await db.document("tasks/\(t.id)").updateData(["commentCount": t.commentCount - 1]) }
                } else { demoComments[r.taskId]?.removeAll { "tasks/\(r.taskId)/comments/\($0.id)" == r.path } }
            case "photo":
                if let t = task(r.taskId) { await removePhoto(t, String(r.path.split(separator: "/").last ?? "")) }
            case "task":
                if let t = task(r.taskId) { archive(t) }
            default: return
            }
            setReport(r, status: "removed")
            toast = "Removed"
        } catch { toast = Self.friendly(error) }
    }
}
