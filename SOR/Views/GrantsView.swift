import SwiftUI

/// The Business board's Grants column: the team's grant and sponsor tracker, as cards next to the task columns.
/// Only admins and Business members see it (firestore.rules: canGrants). Keep the "no AI" banner: the team decided
/// grant writing is done by people.
struct GrantsColumn: View {
    enum Filter: String, CaseIterable { case working = "Working on", submitted = "Submitted", won = "Won", ineligible = "Not eligible", rejected = "Rejected" }
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .working
    @State private var adding = false

    private func matches(_ g: Grant) -> Bool {
        switch filter {
        case .working: g.working || g.status == "not-open"
        case .submitted: g.status == "submitted"
        case .won: g.status == "won"
        case .ineligible: g.status == "not-eligible"
        case .rejected: g.status == "rejected"
        }
    }

    var body: some View {
        let list = model.grants.filter(matches).sorted { a, b in
            let da = Grant.day(a["deadline"]), db = Grant.day(b["deadline"])
            return (da.isEmpty ? "9999" : da, a.name) < (db.isEmpty ? "9999" : db, b.name)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Label("Do NOT use AI in grant writing.", systemImage: "exclamationmark.octagon.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10).glass(14, tint: .red)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            let n = model.grants.filter { g in
                                switch f {
                                case .working: g.working || g.status == "not-open"
                                case .submitted: g.status == "submitted"
                                case .won: g.status == "won"
                                case .ineligible: g.status == "not-eligible"
                                case .rejected: g.status == "rejected"
                                }
                            }.count
                            Button { filter = f } label: {
                                Text("\(f.rawValue) \(n)").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(filter == f ? AnyShapeStyle(Brand.wash(Brand.violet)) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: Capsule())
                                    .foregroundStyle(filter == f ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if filter == .won {
                    let total = model.grants.filter { $0.status == "won" }.map { money($0["wonAmount"].isEmpty ? $0["amount"] : $0["wonAmount"]) }.reduce(0, +)
                    if total > 0 { Text("Won so far: $\(Int(total).formatted())").font(.headline).foregroundStyle(.green) }
                }
                if !model.loaded.contains("grants") && !model.demo { SkeletonRows(count: 4) }
                else if list.isEmpty { Text("Nothing here.").foregroundStyle(.secondary).padding(.top, 20).frame(maxWidth: .infinity) }
                ForEach(list) { g in
                    NavigationLink(value: g) { GrantRow(grant: g) }.buttonStyle(.plain)
                }
                // Tasks filed in the Grants column stay visible under the grants
                let tasks = model.tasks.filter { $0.subteamId == "biz" && $0.columnId == "grants" }.sorted { $0.position < $1.position }
                if !tasks.isEmpty {
                    Text("Tasks").font(.headline).padding(.top, 6)
                    ForEach(tasks) { t in NavigationLink(value: t) { TaskRow(task: t) }.buttonStyle(.plain) }
                }
                HStack(spacing: 10) {
                    NavigationLink(value: GrantPage.library) { Label("Answer library", systemImage: "text.book.closed.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    NavigationLink(value: GrantPage.info) { Label("Team info", systemImage: "info.circle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 6)
                if model.canEdit {
                    Button { adding = true } label: { Label("Add a grant", systemImage: "plus").frame(maxWidth: .infinity).frame(height: 40) }
                        .buttonStyle(.borderedProminent).tint(Brand.violet)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .onAppear { model.wantGrants() }
        .sheet(isPresented: $adding) { NewGrantView() }
    }
}

enum GrantPage: Hashable { case library, info }

/// Largest dollar figure in "$250 - $5,000", "up to $10,000", "5k" (money in mod-grants)
func money(_ text: String) -> Double {
    let re = try! NSRegularExpression(pattern: #"\$?\s*(\d[\d,]*(?:\.\d+)?)\s*(k)?"#, options: .caseInsensitive)
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m -> Double? in
        guard let n = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")) else { return nil }
        return m.range(at: 2).location != NSNotFound ? n * 1000 : n
    }.max() ?? 0
}

struct GrantRow: View {
    @Environment(AppModel.self) private var model
    let grant: Grant
    var body: some View {
        let g = grant
        let due = Grant.day(g["deadline"])
        let days = Day.until(due)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(g.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                Spacer()
                Pill(text: g.statusLabel, tint: g.statusColor)
            }
            FlowLayout(spacing: 8, lineSpacing: 4) {
                if !g["amount"].isEmpty { Label(g["amount"], systemImage: "dollarsign.circle").font(.caption.weight(.medium)) }
                if !due.isEmpty {
                    Label(Day.pretty(due), systemImage: "calendar").font(.caption.weight(.medium))
                        .foregroundStyle(g.working && (days ?? 99) <= 7 ? .orange : .secondary)
                } else if !g["deadline"].isEmpty { Label(g["deadline"], systemImage: "calendar").font(.caption) }
                let writer = model.person(g["writerUid"])?.firstName ?? g["writer"]
                if !writer.isEmpty { Label(writer, systemImage: "pencil").font(.caption) }
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(18, tint: g.statusColor)
    }
}

/// One grant: every field that matters for its status (fieldsFor in mod-grants), edited in place.
struct GrantDetailView: View {
    @Environment(AppModel.self) private var model
    let grantId: String
    @State private var draft: [String: String] = [:]
    @State private var picking: String?

    private static let fields: [(key: String, label: String, kind: String, hint: String)] = [
        ("amount", "Amount", "text", "$5,000 or up to $10,000"),
        ("deadline", "Deadline", "text", "9/24/2026, rolling, not stated"),
        ("draftDue", "Draft due", "text", "9/10/2026 or skip"),
        ("openingDate", "Opens", "text", "or: check regularly"),
        ("submittedOn", "Submitted on", "text", ""),
        ("wonAmount", "Won", "text", "$2,000"),
        ("writer", "Writer", "person", ""), ("secondaryWriter", "2nd writer", "person", ""),
        ("reviewer", "Reviewer", "person", ""), ("foundBy", "Found by", "person", ""),
        ("docUrl", "Grant doc", "url", "Link to our draft"), ("linkUrl", "Application", "url", "Link to the grant's page"),
        ("reason", "Why not eligible", "long", ""), ("reportDeadline", "Report due", "text", "When the sponsor needs an update"),
        ("contactNeeded", "Follow-up", "text", "Newsletter, report, thank-you…"), ("notes", "Notes", "long", ""),
    ]
    private static let uidKey = ["writer": "writerUid", "secondaryWriter": "secondaryUid", "reviewer": "reviewerUid", "foundBy": "foundByUid"]

    private func shown(_ k: String, _ status: String) -> Bool {
        switch k {
        case "openingDate": status == "not-open"
        case "submittedOn": ["submitted", "won", "rejected"].contains(status)
        case "wonAmount", "reportDeadline", "contactNeeded": status == "won"
        case "reason": status == "not-eligible" || status == "rejected"
        case "draftDue": ["not-started", "in-progress", "complete"].contains(status)
        default: true
        }
    }

    var body: some View {
        if let g = model.grants.first(where: { $0.id == grantId }) {
            let edit = model.canEdit
            Form {
                Section {
                    TextField("Name", text: binding(g, "name"), axis: .vertical).font(.title3.weight(.semibold))
                    Picker("Status", selection: Binding(get: { g.status }, set: { model.updateGrant(g, ["status": $0]) })) {
                        ForEach(Grant.statuses, id: \.id) { Text($0.label).tag($0.id) }
                    }
                }
                .listRowBackground(Color.row)
                Section {
                    ForEach(Self.fields.filter { shown($0.key, g.status) }, id: \.key) { f in
                        switch f.kind {
                        case "person":
                            Button { picking = f.key } label: {
                                HStack {
                                    Text(f.label).foregroundStyle(.primary)
                                    Spacer()
                                    let name = model.person(g[Self.uidKey[f.key]!])?.name ?? g[f.key]
                                    Text(name.isEmpty ? "Choose" : name).foregroundStyle(.secondary)
                                }
                            }
                        case "long":
                            VStack(alignment: .leading, spacing: 4) {
                                Text(f.label).font(.caption).foregroundStyle(.secondary)
                                TextField(f.hint, text: binding(g, f.key), axis: .vertical).lineLimit(2...)
                            }
                        case "url":
                            HStack {
                                Text(f.label)
                                TextField(f.hint, text: binding(g, f.key)).multilineTextAlignment(.trailing).keyboardType(.URL).textInputAutocapitalization(.never)
                                if let u = URL(string: g[f.key]), g[f.key].hasPrefix("http") { Link(destination: u) { Image(systemName: "arrow.up.right.square") } }
                            }
                        default:
                            HStack {
                                Text(f.label)
                                TextField(f.hint, text: binding(g, f.key)).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                .listRowBackground(Color.row)
                Section {
                    Text("Do NOT use AI in grant writing.").font(.footnote.weight(.semibold)).foregroundStyle(.red)
                }
                .listRowBackground(Color.row)
            }
            .disabled(!edit)
            .scrollContentBackground(.hidden)
            .appBackground(Brand.violet)
            .navigationTitle("Grant")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(get: { picking.map { WebLink(title: $0, path: $0) } }, set: { picking = $0?.path })) { link in
                PeoplePicker(selected: [g[Self.uidKey[link.path]!]].filter { !$0.isEmpty }) { ids in
                    let id = ids.last ?? ""
                    model.updateGrant(g, [link.path: model.person(id)?.name ?? "", Self.uidKey[link.path]!: id])
                }
            }
            .onDisappear { flush(g) }
        } else {
            ContentUnavailableView("This grant is gone", systemImage: "questionmark.square.dashed")
        }
    }

    /// Text fields save when you leave the page (and as you go, every few keystrokes would be too many writes).
    private func binding(_ g: Grant, _ k: String) -> Binding<String> {
        Binding(get: { draft[k] ?? g[k] }, set: { draft[k] = $0 })
    }

    private func flush(_ g: Grant) {
        let changed = draft.filter { $0.value != g[$0.key] }
        if !changed.isEmpty { model.updateGrant(g, changed) }
        draft = [:]
    }
}

struct NewGrantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var deadline = ""
    @State private var status = "not-started"
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Grant or sponsor", text: $name).font(.title3)
                TextField("Amount ($5,000 or up to $10,000)", text: $amount)
                TextField("Deadline (9/24/2026, rolling…)", text: $deadline)
                Picker("Status", selection: $status) { ForEach(Grant.statuses, id: \.id) { Text($0.label).tag($0.id) } }
            }
            .scrollContentBackground(.hidden)
            .appBackground(Brand.violet)
            .navigationTitle("New grant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saving = true
                        Task {
                            do { try await model.addGrant(name: name, amount: amount, deadline: deadline, status: status); model.toast = "Added “\(name)”"; dismiss() }
                            catch { model.toast = AppModel.friendly(error); saving = false }
                        }
                    }
                    .fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }
}

/// Past application answers, to reuse (read and copy here; written on the website).
struct GrantLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    var body: some View {
        let list = model.grantAnswers.filter { query.isEmpty || [$0.question, $0.answer, $0.grant].contains { $0.localizedCaseInsensitiveContains(query) } }
        let byGrant = Dictionary(grouping: list, by: { $0.grant.isEmpty ? "Other" : $0.grant })
        List {
            if !model.loaded.contains("grantAnswers") && !model.demo { SkeletonRows(count: 4).listRowBackground(Color.clear) }
            ForEach(byGrant.keys.sorted(), id: \.self) { k in
                Section(k) {
                    ForEach(byGrant[k]!) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(a.question).font(.subheadline.weight(.semibold))
                            Text(a.answer).font(.subheadline).foregroundStyle(.secondary).lineLimit(6).textSelection(.enabled)
                            HStack {
                                Text("\(a.answer.split(whereSeparator: \.isWhitespace).count) words\(a.year.isEmpty ? "" : " · \(a.year)")").font(.caption).foregroundStyle(.tertiary)
                                Spacer()
                                Button { UIPasteboard.general.string = a.answer; model.toast = "Copied" } label: { Label("Copy", systemImage: "doc.on.doc") }
                                    .font(.caption).buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.row)
            }
        }
        .searchable(text: $query, prompt: "Search questions and answers")
        .scrollContentBackground(.hidden)
        .appBackground(Brand.violet)
        .navigationTitle("Answer library")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.wantGrantLibrary() }
    }
}

/// The team details grant forms ask for (EIN, address, …), to copy.
struct GrantInfoView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if !model.loaded.contains("grantInfo") && !model.demo { SkeletonRows(count: 4).listRowBackground(Color.clear) }
            ForEach(model.grantInfo) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.label).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text(r.value).textSelection(.enabled)
                        Spacer()
                        Button { UIPasteboard.general.string = r.value; model.toast = "Copied \(r.label)" } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                    }
                    if !r.note.isEmpty { Text(r.note).font(.caption).foregroundStyle(.orange) }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(Color.row)
        }
        .scrollContentBackground(.hidden)
        .appBackground(Brand.violet)
        .navigationTitle("Team info")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.wantGrantLibrary() }
    }
}
