import Foundation
import FirebaseFirestore

/// Leads putting someone on a shift (openAddPeople in mod-shifts): anyone on the roster, account or not.
extension AppModel {
    /// Who someone is for a signup (fromRoster): their account if the roster entry is linked, else r-<rosterId>.
    struct Who: Identifiable, Hashable {
        let key: String, uid: String, rosterId: String, name: String, kind: String, femaleAdult: Bool
        var id: String { key }
    }

    private static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    func wantRoster() {
        guard !demo, phase == .ready, lazyRegs["roster"] == nil else { return }
        lazyRegs["roster"] = db.collection("roster").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                self?.roster = (snap?.documents ?? []).map { RosterPerson(id: $0.documentID, $0.data()) }
                self?.loaded.insert("roster")
            }
        }
        // Whether an adult counts as a female adult: only leads can read everyone's answers
        if isLead && lazyRegs["userDetails"] == nil {
            lazyRegs["userDetails"] = db.collection("userDetails").addSnapshotListener { [weak self] snap, _ in
                MainActor.assumeIsolated {
                    self?.femaleByUid = Dictionary((snap?.documents ?? []).map { ($0.documentID, $0.data().bool("female")) }, uniquingKeysWith: { a, _ in a })
                }
            }
        }
    }

    /// linkedUser in mod-shifts: the roster entry's account, or an approved account with the same name or alias.
    private func linked(_ r: RosterPerson) -> Person? {
        if !r.uid.isEmpty, let p = person(r.uid) { return p }
        let names = Set(([r.name] + r.aliases).map(Self.norm).filter { !$0.isEmpty })
        return users.first { $0.role != .pending && names.contains(Self.norm($0.name)) }
    }

    var rosterPeople: [Who] {
        roster.filter(\.active).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { r in
            let u = linked(r)
            let female = u.flatMap { femaleByUid[$0.id] } ?? r.female
            return Who(key: u?.id ?? "r-\(r.id)", uid: u?.id ?? "", rosterId: r.id, name: r.name, kind: r.kind, femaleAdult: r.kind != "student" && female)
        }
    }

    /// The signup that is this person's, by account or roster entry.
    func signup(of w: Who, at meetingId: String) -> Signup? {
        signups.first { $0.meetingId == meetingId && ($0.uid == w.key || (!w.rosterId.isEmpty && $0.rosterId == w.rosterId)) }
    }

    func addToShift(_ w: Who, _ sh: Shift) async {
        let id = "\(sh.id)__\(w.key)"
        var data: Doc = [
            "meetingId": sh.id, "uid": w.key, "name": w.name, "kind": w.kind, "femaleAdult": w.femaleAdult, "leader": false,
            "title": sh.title, "date": sh.date, "start": sh.start, "end": sh.end, "place": sh.place,
            "online": sh.online, "inPerson": sh.inPerson, "seasonId": currentSeason.id, "at": nowMs, "by": uid,
        ]
        if !w.rosterId.isEmpty { data["rosterId"] = w.rosterId }
        if demo { signups.append(Signup(id: id, data)); return }
        do { try await db.document("signups/\(id)").setData(data) } catch { toast = Self.friendly(error) }
    }
}
