import Foundation
import FirebaseFirestore
import UIKit

/// Team reminders (Action Items › Reminders), promoting action items to tasks, task photos and the grant tracker.
extension AppModel {
    // MARK: Team reminders

    func wantTeamReminders() {
        guard !demo, phase == .ready, canEdit, lazyRegs["teamReminders"] == nil else { return }
        lazyRegs["teamReminders"] = db.collection("teamReminders").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                self?.teamReminders = (snap?.documents ?? []).map { TeamReminder(id: $0.documentID, $0.data()) }
                self?.loaded.insert("teamReminders")
            }
        }
    }

    /// The Slack channel a track's reminders go to (subteams/{board|buildcom}.slackChannel).
    func reminderChannel(_ track: Track) -> String {
        let id = track == .board ? "board" : "buildcom"
        return (subteamDocs[id]?.str("slackChannel") ?? "").trimmingCharacters(in: .whitespaces)
    }

    func addTeamReminder(text: String, track: Track, at date: Date) async throws {
        let sendAt = Int64(date.timeIntervalSince1970 * 1000)
        guard Double(sendAt) > Date().timeIntervalSince1970 * 1000 + 60_000 else { throw AppError("Pick a day and time that haven't passed yet.") }
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let data: Doc = ["text": text.trimmingCharacters(in: .whitespacesAndNewlines), "track": track.rawValue, "date": Day.iso(date), "time": time,
                         "sendAt": sendAt, "createdBy": uid, "createdAt": nowMs]
        if demo { teamReminders.append(TeamReminder(id: UUID().uuidString, data)); return }
        try await db.collection("teamReminders").addDocument(data: data)
    }

    func deleteTeamReminder(_ r: TeamReminder) {
        if demo { teamReminders.removeAll { $0.id == r.id }; return }
        db.document("teamReminders/\(r.id)").delete { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } }
        }
    }

    // MARK: Action items → tasks (promoteAI in mod-views)

    func promote(_ a: ActionItem) async throws -> String {
        let owner = a.ownerUids.first.flatMap(person)
        let boardIds = Set(boards.map(\.id))
        let subteamId = owner?.subteamIds.first { boardIds.contains($0) } ?? profile?.subteamIds.first { boardIds.contains($0) } ?? boards.first?.id ?? ""
        let ev = events.first { $0.id == a.meetingId }
        let id = try await createTask(title: a.text, description: ev.map { "From meeting: \($0.title) (\(Day.pretty($0.dayKey)))" } ?? "",
                                      subteamId: subteamId, columnId: nil, assignees: a.ownerUids, dueDate: a.dueDate, priority: .med)
        patch(a, ["promotedTaskId": id])
        return id
    }

    // MARK: Task photos (photos/{id}: JPEG bytes, ≤900 KB, 14 days unless kept)

    func photo(_ id: String) async -> UIImage? {
        if let img = photoCache[id] { return img }
        guard !demo, let d = try? await db.document("photos/\(id)").getDocument().data(), let bytes = d["data"] as? Data, let img = UIImage(data: bytes) else { return nil }
        photoCache[id] = img
        return img
    }

    /// Scales to at most 1920 px and ≤900 KB as JPEG (fitPhoto in mod-util), then saves it like the website.
    func addPhoto(_ t: TaskItem, _ image: UIImage) async throws {
        guard t.photos.filter({ $0.exp > Date().timeIntervalSince1970 * 1000 }).count < 8 else { throw AppError("A task holds up to 8 photos. Remove one first.") }
        let scale = min(1, 1920 / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let small = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var q: CGFloat = 0.82
        var data = small.jpegData(compressionQuality: q) ?? Data()
        while data.count > 900_000 && q > 0.3 { q -= 0.12; data = small.jpegData(compressionQuality: q) ?? data }
        guard data.count <= 900_000 else { throw AppError("That photo is too big.") }
        let now = nowMs
        let exp = now + 14 * 86_400_000
        let ref = db.collection("photos").document()
        let batch = db.batch()
        batch.setData(["taskId": t.id, "data": data, "type": "image/jpeg", "w": Int(size.width), "h": Int(size.height), "size": data.count,
                       "createdBy": uid, "createdAt": now, "expiresAt": Date(timeIntervalSince1970: Double(exp) / 1000)], forDocument: ref)
        let cur = task(t.id) ?? t
        let list: [Doc] = cur.photos.map { ["id": $0.id, "by": $0.by, "exp": $0.exp] } + [["id": ref.documentID, "by": uid, "at": now, "exp": exp, "w": Int(size.width), "h": Int(size.height)]]
        batch.updateData(["photos": list], forDocument: db.document("tasks/\(t.id)"))
        try await batch.commit()
        photoCache[ref.documentID] = small
    }

    func removePhoto(_ t: TaskItem, _ pid: String) async {
        let cur = task(t.id) ?? t
        let batch = db.batch()
        batch.deleteDocument(db.document("photos/\(pid)"))
        batch.updateData(["photos": cur.photos.filter { $0.id != pid }.map { ["id": $0.id, "by": $0.by, "exp": $0.exp] as Doc }], forDocument: db.document("tasks/\(t.id)"))
        do { try await batch.commit() } catch { toast = Self.friendly(error) }
    }

    // MARK: Grants (Business only: canGrants)

    func wantGrants() {
        guard canGrants, !demo, phase == .ready else { return }
        if lazyRegs["grants"] == nil {
            lazyRegs["grants"] = db.collection("grants").addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    self?.grants = (snap?.documents ?? []).map { Grant(id: $0.documentID, $0.data()) }
                    self?.loaded.insert("grants")
                }
            }
        }
    }

    func wantGrantLibrary() {
        guard canGrants, !demo, phase == .ready else { return }
        if lazyRegs["grantAnswers"] == nil {
            lazyRegs["grantAnswers"] = db.collection("grantAnswers").addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated { self?.grantAnswers = (snap?.documents ?? []).map { GrantAnswer(id: $0.documentID, $0.data()) }; self?.loaded.insert("grantAnswers") }
            }
        }
        if lazyRegs["grantInfo"] == nil {
            lazyRegs["grantInfo"] = db.collection("grantInfo").addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated { self?.grantInfo = (snap?.documents ?? []).map { GrantInfo(id: $0.documentID, $0.data()) }.sorted { $0.position < $1.position }; self?.loaded.insert("grantInfo") }
            }
        }
    }

    func updateGrant(_ g: Grant, _ p: Doc) {
        var patch = p
        patch["updatedAt"] = nowMs
        patch["updatedBy"] = uid
        if demo {
            if let i = grants.firstIndex(where: { $0.id == g.id }) {
                var d: Doc = g.raw
                d["status"] = g.status
                d.merge(patch) { _, n in n }
                grants[i] = Grant(id: g.id, d)
            }
            return
        }
        db.document("grants/\(g.id)").updateData(patch) { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } }
        }
    }

    @discardableResult
    func addGrant(name: String, amount: String, deadline: String, status: String) async throws -> String {
        let data: Doc = [
            "name": name.trimmingCharacters(in: .whitespaces), "amount": amount, "deadline": deadline, "status": status,
            "draftDue": "", "openingDate": "", "writer": "", "writerUid": "", "secondaryWriter": "", "secondaryUid": "",
            "reviewer": "", "reviewerUid": "", "foundBy": profile?.name ?? "", "foundByUid": uid,
            "notes": "", "docUrl": "", "linkUrl": "", "season": "2026-2027", "createdBy": uid, "createdAt": nowMs,
        ]
        if demo { let id = UUID().uuidString; grants.append(Grant(id: id, data)); return id }
        return try await db.collection("grants").addDocument(data: data).documentID
    }
}
