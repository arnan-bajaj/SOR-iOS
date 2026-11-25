import Foundation
import Observation
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

/// Everything the app knows, kept live by Firestore listeners, plus every write it makes.
/// Writes mirror the web app's shapes exactly (index.html), and firestore.rules decide what is allowed,
/// the same as on the website.
@Observable @MainActor
final class AppModel {
    enum Phase: Equatable { case notConfigured, starting, signedOut, loadingProfile, onboarding, pending, ready, failed(String) }

    var phase: Phase = .starting
    var uid = ""
    var authName = ""
    var authEmail = ""
    var authPhoto = ""

    var profile: Person?
    var users: [Person] = []
    var subteams: [Subteam] = []
    var columns: [BoardColumn] = []
    var allTasks: [TaskItem] = []
    var settings: [String: Doc] = [:]
    var seasonDocs: [Season] = []
    var meetingExtras: [String: Doc] = [:]
    var arrivals: [Arrival] = []
    var signups: [Signup] = []
    var myMarks: [Mark] = []
    var myFemale: Bool?
    var actionItems: [ActionItem] = []
    var privateActionItems: [ActionItem] = []
    var agendas: [Agenda] = []
    var events: [CalEvent] = []
    var loaded: Set<String> = []
    var toast: String?
    /// Saving the first-time answers failed: let them in anyway, like the website does.
    var askSkipped = false
    /// Your users/{uid} document as stored (push settings live in it).
    var profileDoc: Doc = [:]
    var openLink: AppLink?
    var showHelper = false
    var pushAllowed = true
    @ObservationIgnored var pushToken: String?
    @ObservationIgnored var pendingPushToken: String?
    @ObservationIgnored var widgetTimer: Timer?
    /// For the app delegate (push tokens, tapped notifications), which SwiftUI doesn't hand the model to.
    @ObservationIgnored static weak var shared: AppModel?

    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var profileReg: ListenerRegistration?
    @ObservationIgnored private var teamRegs: [ListenerRegistration] = []
    @ObservationIgnored private var lastIcs = ""
    @ObservationIgnored private var creatingProfile = false
    @ObservationIgnored private var autoAdmin = false
    @ObservationIgnored private var arrivalsDay = ""
    @ObservationIgnored private var boardRoomReg: ListenerRegistration?
    @ObservationIgnored private var agendasReg: ListenerRegistration?
    /// Listeners started the first time a page needs them (Board Room, agenda documents, the team's attendance).
    @ObservationIgnored var lazyRegs: [String: ListenerRegistration] = [:]
    var boardChannel: [ChannelMessage] = []
    var agendaDocs: [AgendaDoc] = []
    var boardAgendaDocs: [AgendaDoc] = []
    var googleDocs: [GoogleDoc] = []
    var boardGoogleDocs: [GoogleDoc] = []
    var teamMarks: [Mark] = []
    var isHelperReviewer = false
    var roster: [RosterPerson] = []
    var teamReminders: [TeamReminder] = []
    /// reports/{id}: admins only (AppModel+Safety)
    var reports: [Report] = []
    /// People you've blocked, on this phone (AppModel+Safety)
    var blockedUids: Set<String> = []
    /// Subteam documents as stored (for fields the app rarely needs, like slackChannel)
    var subteamDocs: [String: Doc] = [:]
    @ObservationIgnored var photoCache: [String: UIImage] = [:]
    var femaleByUid: [String: Bool] = [:]

    /// Must match OWNER_EMAILS in index.html and isAutoAdmin() in firestore.rules.
    static let ownerEmails = ["rishik.kasula42@gmail.com"]
    /// The website. `-site http://localhost:5173` points a debug run at the local server instead.
    static let site: URL = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-site"), i + 1 < args.count, let u = URL(string: args[i + 1]) { return u }
        return URL(string: "https://team.systemoverload.org")!
    }()

    var db: Firestore { Firestore.firestore() }

    // MARK: - Permissions (can.* in mod-state)

    var role: Role { profile?.role ?? .pending }
    var canRead: Bool { role.rank >= Role.viewer.rank }
    var canEdit: Bool { role.rank >= Role.member.rank }
    var isLead: Bool { role.rank >= Role.lead.rank }
    var isAdmin: Bool { role == .admin }
    func canDelete(_ t: TaskItem) -> Bool { isLead || (canEdit && t.createdBy == uid) }

    /// holdsIn in mod-state: on the leadership roster's list for that group, by email or linked account.
    private func holds(_ group: String, _ stored: String) -> Bool {
        guard let doc = settings["leadership"] else { return false }
        var emails = Set(doc.strs(stored).map { $0.lowercased() })
        let positions = doc.docs("positions").filter { $0.str("group") == group }
        for p in positions {
            for h in p.docs("holders") {
                if !h.str("email").isEmpty { emails.insert(h.str("email").lowercased()) }
                if !h.str("uid").isEmpty && h.str("uid") == uid { return true }
            }
        }
        return !authEmail.isEmpty && emails.contains(authEmail)
    }
    /// Writes confidential action items (isBoardMember).
    var isBoardMember: Bool { demo ? isAdmin : holds("Board", "boardEmails") }
    var isLeadMentor: Bool { demo ? false : holds("Lead mentors", "leadMentorEmails") }
    var canSeeBoardRoom: Bool { isBoardMember || isLeadMentor }
    var isParent: Bool { profile?.memberType == "parent" }

    // MARK: - Lookups

    func person(_ id: String) -> Person? { users.first { $0.id == id } }
    func subteam(_ id: String) -> Subteam? { subteams.first { $0.id == id } }
    func task(_ id: String) -> TaskItem? { allTasks.first { $0.id == id } }

    var seasons: [Season] {
        let list = seasonDocs.filter { !$0.archived }.sorted { $0.start < $1.start }
        return list.isEmpty ? Season.defaults : list
    }
    /// activeSeason() in mod-state: the team's chosen season, else the planned one for today, else the last.
    /// seasonFrom in mod-state: the first day that can belong to the open season.
    var seasonFrom: String {
        let s = currentSeason
        let team = settings["season"]
        if let team, team.str("activeId") == s.id, !team.str("since").isEmpty, team.str("since") < s.start { return team.str("since") }
        return s.start
    }
    var currentSeason: Season {
        let list = seasons
        let today = Day.iso()
        if let id = settings["season"]?.str("activeId"), let s = list.first(where: { $0.id == id }) { return s }
        return list.first { $0.start <= today && today <= $0.end } ?? list[list.count - 1]
    }
    /// The open season's tasks that aren't archived.
    var tasks: [TaskItem] {
        let sid = currentSeason.id
        return allTasks.filter { $0.seasonId == sid && !$0.archived }
    }
    /// Boards that hold tasks: not Team Goals (the Priorities column) and not Board / Build Committee (action items).
    var boards: [Subteam] {
        subteams.filter { !["goals", "board", "buildcom"].contains($0.id) }.sorted { $0.position < $1.position }
    }
    func columns(for subteam: String) -> [BoardColumn] {
        columns.filter { $0.subteamIds.isEmpty || subteam == "all" || $0.subteamIds.contains(subteam) }.sorted { $0.position < $1.position }
    }
    var doneColumnId: String {
        let cols = columns.sorted { $0.position < $1.position }
        return cols.first { $0.id == "done" }?.id ?? cols.last?.id ?? "done"
    }
    func isDone(_ t: TaskItem) -> Bool { t.columnId == doneColumnId }
    func columnName(_ id: String) -> String { columns.first { $0.id == id }?.name ?? id }

    var myOpenTasks: [TaskItem] {
        tasks.filter { ($0.assigneeUids.contains(uid) || $0.backupUids.contains(uid)) && !isDone($0) }
            .sorted { a, b in
                switch (a.dueDate.isEmpty, b.dueDate.isEmpty) {
                case (false, true): return true
                case (true, false): return false
                case (false, false) where a.dueDate != b.dueDate: return a.dueDate < b.dueDate
                default: return a.priority.rank < b.priority.rank
                }
            }
    }
    var teammates: [Person] {
        users.filter { $0.role.rank >= Role.member.rank }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Meetings

    func isCancelled(_ e: CalEvent) -> Bool { meetingExtras[e.id]?.bool("cancelled") ?? false }
    var upcoming: [CalEvent] { events.filter { $0.end > Date().timeIntervalSince1970 * 1000 } }
    var nextCompetition: CalEvent? { upcoming.first { $0.isCompetition && !$0.isNotCompeting } }
    /// A meeting in person happening now or within the hour: the "I'm here" button shows for it.
    var meetingNow: CalEvent? {
        let now = Date().timeIntervalSince1970 * 1000
        return events.first { !$0.allDay && !$0.place.isEmpty && !isCancelled($0) && $0.start - 3_600_000 <= now && now <= $0.end }
    }
    var imHere: Bool { arrivals.contains { $0.id == "\(Day.iso())__\(uid)" } }
    /// The Slack post that covers a meeting, from settings/slackSignups (kept by the bot).
    func slackSignupURL(_ meetingId: String) -> URL? {
        guard let m = (settings["slackSignups"]?["meetings"] as? Doc)?[meetingId] as? Doc else { return nil }
        let ch = m.str("channel"), ts = m.str("ts")
        guard ch.range(of: #"^[A-Z0-9]+$"#, options: .regularExpression) != nil, ts.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://trivalleyrobotics.slack.com/archives/\(ch)/p\(ts.replacingOccurrences(of: ".", with: ""))")
    }

    // MARK: - Start up and sign in

    /// Demo mode (launch argument `-demo`): invented people and tasks, nothing read from or written to the team's database.
    /// For the Simulator, screenshots, and trying things safely.
    @ObservationIgnored var demo = false
    @ObservationIgnored var demoDocs: [String: Doc] = [:]
    @ObservationIgnored var demoComments: [String: [Comment]] = [:]

    func start() {
        guard authHandle == nil else { return }
        if ProcessInfo.processInfo.arguments.contains("-demo") { startDemo(); return }
        guard let app = FirebaseApp.app() else { phase = .notConfigured; return }
        if let clientID = app.options.clientID { GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID) }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.authChanged(user) }
        }
    }

    /// Google is how the team signs in; email and password is the "Other sign-in" (accounts an admin makes in Firebase).
    var signedInWithGoogle: Bool { Auth.auth().currentUser?.providerData.contains { $0.providerID == "google.com" } ?? false }

    func signIn(email: String, password: String) async -> String? {
        do {
            try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
            return nil
        } catch let e as NSError {
            switch AuthErrorCode(rawValue: e.code) {
            case .wrongPassword, .invalidCredential, .userNotFound, .invalidEmail: return "That email and password don't match an account."
            case .operationNotAllowed: return "Email sign-in isn't turned on for this team yet."
            case .tooManyRequests: return "Too many tries. Wait a minute and try again."
            case .networkError: return "No connection. Check your internet and try again."
            default: return e.localizedDescription
            }
        }
    }

    func signIn() async {
        guard FirebaseApp.app()?.options.clientID != nil else {
            toast = "Google sign-in isn't set up in this build yet (GoogleService-Info.plist has no client ID)."
            return
        }
        guard let presenter = UIApplication.shared.topViewController else { return }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw AppError("Google didn't send a sign-in token. Try again.") }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
        } catch let e as NSError where e.domain == kGIDSignInErrorDomain && e.code == GIDSignInError.canceled.rawValue {
            return
        } catch {
            toast = error.localizedDescription
        }
    }

    func signOut() {
        if demo { leaveDemo(); return }
        Task {
            await forgetPushToken() // while still signed in, so the rules allow it
            GIDSignIn.sharedInstance.signOut()
            try? Auth.auth().signOut()
        }
    }

    private func authChanged(_ user: User?) {
        if demo && user == nil { return } // looking around the demo: nobody's signed in, and that's fine
        if demo { leaveDemo() }
        stopAll()
        guard let user else {
            uid = ""; profile = nil
            phase = .signedOut
            return
        }
        uid = user.uid
        authEmail = (user.email ?? "").lowercased()
        authName = user.displayName ?? user.email ?? ""
        // Firebase keeps the photo from someone's first sign-in; the Google entry is refreshed every sign-in.
        authPhoto = user.providerData.first { $0.providerID == "google.com" }?.photoURL?.absoluteString ?? user.photoURL?.absoluteString ?? ""
        phase = .loadingProfile
        Task { await watchProfile(user) }
    }

    private func watchProfile(_ user: User) async {
        // The owner, or someone on the leadership roster's admin list, is an admin from the first sign-in.
        autoAdmin = Self.ownerEmails.contains(authEmail)
        if !autoAdmin, let doc = try? await db.document("settings/leadership").getDocument(), let d = doc.data() {
            autoAdmin = d.strs("adminEmails").contains(authEmail)
        }
        guard uid == user.uid else { return }
        profileReg = db.document("users/\(user.uid)").addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let err { self.phase = .failed("Couldn't load your profile: \(err.localizedDescription)"); return }
                guard let snap else { return }
                self.profileChanged(snap)
            }
        }
    }

    private func profileChanged(_ snap: DocumentSnapshot) {
        guard let data = snap.data() else {
            // First sign-in: create a pending profile, the same document the website makes. An admin approves it.
            guard !creatingProfile else { return }
            creatingProfile = true
            db.document("users/\(uid)").setData([
                "name": authName, "email": authEmail, "photoURL": authPhoto,
                "role": autoAdmin ? "admin" : "pending", "subteamIds": [String](), "createdAt": nowMs,
            ]) { [weak self] err in
                MainActor.assumeIsolated { if let err { self?.phase = .failed("Couldn't create your profile: \(err.localizedDescription)") } }
            }
            return
        }
        let p = Person(id: snap.documentID, data)
        profile = p
        profileDoc = data
        if autoAdmin && p.role != .admin { db.document("users/\(uid)").updateData(["role": "admin"]) }
        // Keep the Google name and photo in step, unless an admin renamed them (nameEdited).
        var sync: Doc = [:]
        if !authName.isEmpty && p.name != authName && !data.bool("nameEdited") { sync["name"] = authName }
        if !authPhoto.isEmpty && p.photoURL != authPhoto { sync["photoURL"] = authPhoto }
        if !sync.isEmpty { db.document("users/\(uid)").updateData(sync) }

        if p.onboardedAt == 0 && !askSkipped { stopTeam(); phase = .onboarding; return }
        if !canRead { stopTeam(); phase = .pending; return }
        if teamRegs.isEmpty { startTeam() }
        if phase != .ready {
            loadBlocked()
            phase = .ready
            setUpPush()
            if let t = pendingPushToken { pendingPushToken = nil; savePushToken(t) }
        }
    }

    // MARK: - Live data

    private func listen(_ name: String, _ query: Query, _ apply: @escaping ([QueryDocumentSnapshot]) -> Void) {
        let reg = query.addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated {
                if let err { print("listener \(name):", err.localizedDescription); return }
                guard let docs = snap?.documents else { return }
                apply(docs)
                self?.loaded.insert(name)
            }
        }
        teamRegs.append(reg)
    }

    private func startTeam() {
        listen("users", db.collection("users")) { [weak self] in self?.users = $0.map { Person(id: $0.documentID, $0.data()) } }
        listen("subteams", db.collection("subteams")) { [weak self] docs in
            self?.subteams = docs.map { Subteam(id: $0.documentID, $0.data()) }
            self?.subteamDocs = Dictionary(docs.map { ($0.documentID, $0.data()) }, uniquingKeysWith: { a, _ in a })
        }
        listen("columns", db.collection("columns")) { [weak self] in self?.columns = $0.map { BoardColumn(id: $0.documentID, $0.data()) } }
        listen("tasks", db.collection("tasks")) { [weak self] in self?.allTasks = $0.map { TaskItem(id: $0.documentID, $0.data()) }; self?.updateWidget() }
        listen("seasons", db.collection("seasons")) { [weak self] in self?.seasonDocs = $0.map { Season(id: $0.documentID, $0.data()) } }
        listen("meetings", db.collection("meetings")) { [weak self] in
            self?.meetingExtras = Dictionary($0.map { ($0.documentID, $0.data()) }, uniquingKeysWith: { a, _ in a })
        }
        // The website's window: the last 150 days, or the season's start if that's earlier.
        let back = Day.iso(Date().addingTimeInterval(-150 * 86400))
        listen("signups", db.collection("signups").whereField("date", isGreaterThanOrEqualTo: min(back, seasonFrom))) { [weak self] in
            self?.signups = $0.map { Signup(id: $0.documentID, $0.data()) }
            self?.updateWidget()
        }
        listen("attendance", db.collection("attendance").whereField("uid", isEqualTo: uid)) { [weak self] in
            self?.myMarks = $0.map { Mark(id: $0.documentID, $0.data()) }
        }
        listen("actionItems", db.collection("actionItems")) { [weak self] in
            self?.actionItems = $0.map { ActionItem(id: $0.documentID, $0.data()) }
        }
        // Your private answers (only you and leads can read them): whether a signup counts as a female adult.
        teamRegs.append(db.document("userDetails/\(uid)").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated { self?.myFemale = snap?.data().map { $0.bool("female") } }
        })
        listen("settings", db.collection("settings")) { [weak self] docs in
            guard let self else { return }
            self.settings = Dictionary(docs.map { ($0.documentID, $0.data()) }, uniquingKeysWith: { a, _ in a })
            self.refreshCalendar()
            self.watchBoardRoom()
        }
        watchArrivals()
        Task { await checkHelperReviewer() }
    }

    /// Today's "I'm here" check-ins. Re-pointed at the new day when the app comes back after midnight.
    func watchArrivals() {
        let day = Day.iso()
        guard day != arrivalsDay, !teamRegs.isEmpty else { return }
        arrivalsDay = day
        listen("arrivals", db.collection("arrivals").whereField("day", isEqualTo: day)) { [weak self] in
            self?.arrivals = $0.map { Arrival(id: $0.documentID, $0.data()) }.sorted { $0.at > $1.at }
        }
    }

    /// The calendar the bot keeps in settings/calendar, expanded around today.
    func refreshCalendar(force: Bool = false) {
        guard let ics = settings["calendar"]?.str("ics"), !ics.isEmpty, force || ics != lastIcs else { return }
        lastIcs = ics
        Task.detached(priority: .userInitiated) {
            let list = TeamCalendar.events(fromICS: ics)
            await MainActor.run { self.events = list; self.loaded.insert("calendar"); self.updateWidget() }
        }
    }

    /// Confidential action items: only the Board and lead mentors can load them (the rules refuse anyone else).
    private func watchBoardRoom() {
        guard canSeeBoardRoom, boardRoomReg == nil, !demo else { return }
        boardRoomReg = db.collection("privateActionItems").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                self?.privateActionItems = (snap?.documents ?? []).map { ActionItem(id: $0.documentID, $0.data(), confidential: true) }
                self?.loaded.insert("privateActionItems")
            }
        }
        teamRegs.append(boardRoomReg!)
    }

    /// Hangar agendas load the first time someone opens them (the website's want("agendas")).
    func wantAgendas() {
        guard agendasReg == nil, !teamRegs.isEmpty, !demo else { return }
        agendasReg = db.collection("agendas").addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated {
                self?.agendas = (snap?.documents ?? []).map { Agenda(id: $0.documentID, $0.data()) }
                self?.loaded.insert("agendas")
            }
        }
        teamRegs.append(agendasReg!)
    }

    private func stopTeam() {
        boardRoomReg = nil; agendasReg = nil
        lazyRegs.values.forEach { $0.remove() }
        lazyRegs = [:]
        teamRegs.forEach { $0.remove() }
        teamRegs = []
        arrivalsDay = ""
    }

    private func stopAll() {
        profileReg?.remove(); profileReg = nil
        stopTeam()
        creatingProfile = false
        users = []; subteams = []; columns = []; allTasks = []; settings = [:]; arrivals = []; signups = []; myMarks = []; events = []; loaded = []
        actionItems = []; privateActionItems = []; agendas = []; myFemale = nil
        boardRoomReg = nil; agendasReg = nil
        lastIcs = ""
    }

    // MARK: - Writes

    /// The questions everyone answers once (mod-app saveAnswers).
    func skipAnswers() {
        askSkipped = true
        if let p = profile { phase = p.role.rank >= Role.viewer.rank ? .ready : .pending; if phase == .ready && teamRegs.isEmpty { startTeam() } }
    }

    func saveAnswers(female: Bool, memberType: String) async throws {
        let at = nowMs
        let batch = db.batch()
        batch.setData(["female": female, "at": at], forDocument: db.document("userDetails/\(uid)"))
        batch.updateData(["memberType": memberType, "onboardedAt": at], forDocument: db.document("users/\(uid)"))
        try await batch.commit()
    }

    func newTaskPosition(_ columnId: String) -> Double {
        let inCol = tasks.filter { $0.columnId == columnId }.map(\.position)
        return (inCol.max() ?? 0) + 1000
    }

    /// The same document the website's task editor makes.
    @discardableResult
    func createTask(title: String, description: String, subteamId: String, columnId: String?, assignees: [String],
                    dueDate: String, priority: Priority) async throws -> String {
        let cols = columns(for: subteamId)
        let col = columnId ?? cols.first { $0.id == "todo" }?.id ?? cols.first?.id ?? "todo"
        let data: Doc = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines), "description": description, "columnId": col, "subteamId": subteamId,
            "assigneeUids": assignees, "backupUids": [String](), "dueDate": dueDate, "startDate": "", "estHours": "", "flagged": false, "dod": "",
            "priority": priority.rawValue, "subsystem": "", "checklist": [Doc](), "blockedBy": [String](), "childIds": [String](), "isGoal": false,
            "reminders": [90], "seasonId": currentSeason.id, "position": newTaskPosition(col),
            "createdBy": uid, "createdAt": nowMs, "commentCount": 0,
        ]
        if demo {
            let id = "demo-\(UUID().uuidString.prefix(8))"
            demoDocs[id] = data
            allTasks.append(TaskItem(id: id, data))
            return id
        }
        let ref = try await db.collection("tasks").addDocument(data: data)
        return ref.documentID
    }

    func update(_ t: TaskItem, _ patch: Doc) {
        var p = patch
        p["updatedAt"] = nowMs
        if demo {
            var d = demoDocs[t.id] ?? [:]
            d.merge(p) { _, new in new }
            demoDocs[t.id] = d
            if let i = allTasks.firstIndex(where: { $0.id == t.id }) { allTasks[i] = TaskItem(id: t.id, d) }
            return
        }
        db.document("tasks/\(t.id)").updateData(p) { [weak self] err in
            MainActor.assumeIsolated { if let err { self?.toast = Self.friendly(err) } }
        }
    }

    func move(_ t: TaskItem, to columnId: String) {
        update(t, ["columnId": columnId, "position": newTaskPosition(columnId)])
    }

    func archive(_ t: TaskItem) { update(t, ["archived": true, "archivedAt": nowMs]) }
    func unarchive(_ t: TaskItem) { update(t, ["archived": false, "archivedAt": 0]) }

    func setChecklist(_ t: TaskItem, _ list: [ChecklistItem]) {
        update(t, ["checklist": list.map { ["text": $0.text, "done": $0.done] as Doc }])
    }

    func addComment(_ t: TaskItem, _ body: String) async throws {
        if demo {
            demoComments[t.id, default: []].append(Comment(id: UUID().uuidString, ["authorId": uid, "body": body, "createdAt": nowMs]))
            update(t, ["commentCount": t.commentCount + 1])
            return
        }
        try await db.collection("tasks/\(t.id)/comments").addDocument(data: ["authorId": uid, "body": body, "createdAt": nowMs])
        let count = task(t.id)?.commentCount ?? t.commentCount
        try? await db.document("tasks/\(t.id)").updateData(["commentCount": count + 1])
    }

    /// Live comments on a task. Call the returned function to stop listening.
    func comments(_ taskId: String, _ onChange: @escaping ([Comment]) -> Void) -> () -> Void {
        if demo {
            onChange(demoComments[taskId] ?? [])
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { onChange(self?.demoComments[taskId] ?? []) }
            }
            return { timer.invalidate() }
        }
        let reg = db.collection("tasks/\(taskId)/comments").addSnapshotListener { snap, _ in
            let list = (snap?.documents ?? []).map { Comment(id: $0.documentID, $0.data()) }.sorted { $0.createdAt < $1.createdAt }
            MainActor.assumeIsolated { onChange(list) }
        }
        return { reg.remove() }
    }

    /// "I'm here": one document per person per day (mod-arrivals announceArrival). The meeting-room Monitor rings for it.
    func announceArrival() async {
        let day = Day.iso()
        let doc: Doc = ["uid": uid, "name": profile?.name ?? authName, "photoURL": authPhoto, "day": day, "at": nowMs]
        if demo { arrivals.insert(Arrival(id: "\(day)__\(uid)", doc), at: 0); toast = "The team knows you're here."; return }
        do {
            try await db.document("arrivals/\(day)__\(uid)").setData(doc)
            toast = "The team knows you're here."
        } catch { toast = Self.friendly(error) }
    }

    // MARK: - Deleting your account

    /// Deletes what's yours, then the sign-in itself. Google asks you to sign in again first, because removing
    /// an account needs a fresh sign-in. Team records (tasks you made, attendance, comments) stay with the team.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser, let presenter = UIApplication.shared.topViewController else { return }
        if signedInWithGoogle {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: authEmail, additionalScopes: nil)
            guard let idToken = result.user.idToken?.tokenString else { throw AppError("Google didn't confirm the sign-in.") }
            try await user.reauthenticate(with: GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString))
        } else if let at = user.metadata.lastSignInDate, Date().timeIntervalSince(at) > 300 {
            // Firebase only deletes an email sign-in that's fresh
            throw AppError("For your safety, sign out and sign back in, then delete your account.")
        }

        let me = uid
        await forgetPushToken()
        profileReg?.remove(); profileReg = nil
        stopTeam()
        // Each can be refused until the rules let people delete their own documents; the account still goes.
        try? await db.document("arrivals/\(Day.iso())__\(me)").delete()
        try? await db.document("userDetails/\(me)").delete()
        try? await db.document("users/\(me)").delete()
        try await user.delete()
        GIDSignIn.sharedInstance.signOut()
    }

    static func friendly(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == FirestoreErrorDomain && e.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You don't have permission to do that."
        }
        return e.localizedDescription
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

extension UIApplication {
    var topViewController: UIViewController? {
        var vc = connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}
