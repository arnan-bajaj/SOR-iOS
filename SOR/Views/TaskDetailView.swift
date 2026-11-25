import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    let taskId: String

    @State private var title = ""
    @State private var notes = ""
    @State private var newItem = ""
    @State private var comment = ""
    @State private var comments: [Comment] = []
    @State private var reporting: ReportTarget?
    @State private var stopComments: (() -> Void)?
    @State private var pickingPeople = false
    @State private var pickingBackups = false
    @State private var pickingDeps = false
    @State private var pickingParts = false
    @State private var dod = ""
    @State private var est = ""
    @State private var subsystem = ""
    @State private var sending = false
    @FocusState private var focus: Field?
    enum Field { case title, notes, item, comment, dod, est, subsystem }

    var body: some View {
        if let t = model.task(taskId) {
            content(t)
        } else {
            ContentUnavailableView("This task is gone", systemImage: "questionmark.square.dashed", description: Text("Someone archived or deleted it."))
        }
    }

    private func content(_ t: TaskItem) -> some View {
        let edit = model.canEdit
        return Form {
            Section {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .focused($focus, equals: .title)
                    .disabled(!edit)
                    .onSubmit { saveTitle(t) }
                if let s = model.subteam(t.subteamId) {
                    HStack(spacing: 6) { SubteamDot(color: s.color); Text(s.name).foregroundStyle(.secondary) }.font(.subheadline)
                }
            }
            Section {
                Picker("Status", selection: Binding(get: { t.columnId }, set: { model.move(t, to: $0) })) {
                    ForEach(model.columns(for: t.subteamId)) { Text($0.name).tag($0.id) }
                }
                Picker("Priority", selection: Binding(get: { t.priority }, set: { model.update(t, ["priority": $0.rawValue]) })) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
                dueRow(t)
                Button { pickingPeople = true } label: {
                    HStack {
                        Text("Owner").foregroundStyle(.primary)
                        Spacer()
                        if t.assigneeUids.isEmpty { Text("Nobody").foregroundStyle(.secondary) }
                        else {
                            AvatarStack(ids: t.assigneeUids)
                            Text(t.assigneeUids.compactMap { model.person($0)?.firstName }.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .disabled(!edit)
            .listRowBackground(Color.row)

            Section {
                ReminderChips(on: t.reminders) { model.update(t, ["reminders": $0]) }.disabled(!edit || t.dueDate.isEmpty)
            } header: { Text("Remind in Slack") } footer: {
                Text(t.dueDate.isEmpty ? "Give it a due date to get reminders." : "Posted in the board's Slack channel when that much of the time to the due date has gone by. The people on it get a push too.")
            }
            .listRowBackground(Color.row)

            goalSection(t, edit)

            Section("Details") {
                Button { pickingBackups = true } label: {
                    HStack {
                        Text("Backup").foregroundStyle(.primary)
                        Spacer()
                        Text(t.backupUids.isEmpty ? "Nobody" : t.backupUids.compactMap { model.person($0)?.firstName }.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                optionalDate("Start date", t.startDate) { model.update(t, ["startDate": $0]) }
                if !t.dueDate.isEmpty || !t.newDueDate.isEmpty {
                    optionalDate("Second deadline", t.newDueDate) { model.update(t, ["newDueDate": $0]) }
                }
                Button { pickingDeps = true } label: {
                    HStack {
                        Text("Blocked by").foregroundStyle(.primary)
                        Spacer()
                        Text(t.blockedBy.isEmpty ? "Nothing" : t.blockedBy.compactMap { model.task($0)?.title }.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ForEach(t.blockedBy.compactMap { model.task($0) }) { d in
                    NavigationLink(value: d) {
                        Label(d.title, systemImage: model.isDone(d) ? "checkmark.circle.fill" : model.isLate(d) ? "exclamationmark.circle.fill" : "circle")
                            .foregroundStyle(model.isDone(d) ? .secondary : .primary).font(.subheadline)
                    }
                }
                HStack {
                    Text("Est. hours")
                    TextField("0", text: $est).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focus, equals: .est)
                }
                HStack {
                    Text("Subsystem")
                    TextField("e.g. Intake", text: $subsystem).multilineTextAlignment(.trailing).focused($focus, equals: .subsystem)
                }
                Toggle(isOn: Binding(get: { t.flagged }, set: { model.update(t, ["flagged": $0]) })) { Label("Flag for attention", systemImage: "flag.fill") }
                    .tint(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Definition of done").font(.caption).foregroundStyle(.secondary)
                    TextField("How will you know this is finished?", text: $dod, axis: .vertical).focused($focus, equals: .dod)
                }
            }
            .disabled(!edit)
            .listRowBackground(Color.row)

            PhotosSection(task: t, edit: edit && !model.isDone(t))

            let agendas = model.agendas.filter { !$0.removed && $0.taskIds.contains(t.id) }
            if !agendas.isEmpty {
                Section("On hangar agendas") {
                    ForEach(agendas) { a in Label("\(a.title) · \(Day.pretty(a.date))", systemImage: "list.bullet.rectangle") }
                }
                .listRowBackground(Color.row)
            }

            Section("Notes") {
                TextField("Add notes", text: $notes, axis: .vertical)
                    .lineLimit(3...)
                    .focused($focus, equals: .notes)
                    .disabled(!edit)
            }

            Section("Checklist") {
                ForEach(Array(t.checklist.enumerated()), id: \.offset) { i, item in
                    Button {
                        var list = t.checklist
                        list[i].done.toggle()
                        model.setChecklist(t, list)
                    } label: {
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? .green : .secondary)
                            Text(item.text).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                        }
                    }
                    .disabled(!edit)
                }
                .onDelete(perform: edit ? { idx in var list = t.checklist; list.remove(atOffsets: idx); model.setChecklist(t, list) } : nil)
                if edit {
                    HStack {
                        Image(systemName: "plus.circle").foregroundStyle(.secondary)
                        TextField("Add a step", text: $newItem).focused($focus, equals: .item).submitLabel(.done)
                            .onSubmit {
                                let text = newItem.trimmingCharacters(in: .whitespaces)
                                guard !text.isEmpty else { return }
                                model.setChecklist(t, t.checklist + [ChecklistItem(text: text, done: false)])
                                newItem = ""
                                focus = .item
                            }
                    }
                }
            }

            Section("Comments") {
                let shown = comments.filter { !model.isBlocked($0.authorId) }
                if shown.isEmpty { Text("No comments yet.").foregroundStyle(.secondary) }
                ForEach(shown) { c in
                    HStack(alignment: .top, spacing: 10) {
                        PersonAvatar(id: c.authorId, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.person(c.authorId)?.name ?? "Someone").font(.subheadline.weight(.semibold))
                                Text(Date(timeIntervalSince1970: c.createdAt / 1000), format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(c.body)
                        }
                    }
                    .contextMenu {
                        ReportMenuItems(target: ReportTarget(kind: "comment", path: "tasks/\(t.id)/comments/\(c.id)", taskId: t.id, authorUid: c.authorId, text: c.body)) { reporting = $0 }
                    }
                }
                if shown.count < comments.count {
                    Text("Comments from people you blocked are hidden.").font(.caption).foregroundStyle(.secondary)
                }
                if edit {
                    HStack(alignment: .bottom) {
                        TextField("Write a comment", text: $comment, axis: .vertical).focused($focus, equals: .comment)
                        Button {
                            send(t)
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    }
                }
            }

            Section {
                ShareLink(item: AppModel.site.appending(path: "task/\(t.id)")) { Label("Share link", systemImage: "link") }
                if t.createdBy != model.uid {
                    Button { reporting = ReportTarget(kind: "task", path: "tasks/\(t.id)", taskId: t.id, authorUid: t.createdBy, text: [t.title, t.description].filter { !$0.isEmpty }.joined(separator: "\n")) } label: {
                        Label("Report this task", systemImage: "exclamationmark.bubble")
                    }
                }
                if model.canDelete(t) {
                    Button(role: .destructive) {
                        model.archive(t)
                        model.toast = "Archived “\(t.title)”"
                    } label: { Label("Archive", systemImage: "archivebox") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focus != nil {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { focus = nil } }
            }
        }
        .sheet(item: $reporting) { ReportSheet(target: $0) }
        .sheet(isPresented: $pickingPeople) {
            PeoplePicker(selected: t.assigneeUids) { model.update(t, ["assigneeUids": $0]) }
        }
        .sheet(isPresented: $pickingBackups) {
            PeoplePicker(selected: t.backupUids) { model.update(t, ["backupUids": $0]) }
        }
        .sheet(isPresented: $pickingDeps) {
            TaskPicker(title: "Blocked by", selected: t.blockedBy, exclude: t.id) { model.update(t, ["blockedBy": $0]) }
        }
        .sheet(isPresented: $pickingParts) {
            TaskPicker(title: "What it's made of", selected: t.childIds, exclude: t.id) { model.update(t, ["childIds": $0]) }
        }
        .onAppear {
            title = t.title
            notes = t.description
            dod = t.dod
            est = t.estHours
            subsystem = t.subsystem
            model.wantAgendas()
            stopComments = model.comments(t.id) { comments = $0 }
        }
        .onDisappear { stopComments?() }
        .onChange(of: focus) { old, _ in
            // Save a field when you leave it, like the website's editor.
            if old == .title { saveTitle(t) }
            if old == .notes, notes != t.description { model.update(t, ["description": notes]) }
            if old == .dod, dod != t.dod { model.update(t, ["dod": dod]) }
            if old == .est, est != t.estHours { model.update(t, ["estHours": est]) }
            if old == .subsystem, subsystem != t.subsystem { model.update(t, ["subsystem": subsystem]) }
        }
        .onChange(of: t.title) { _, new in if focus != .title { title = new } }
        .onChange(of: t.description) { _, new in if focus != .notes { notes = new } }
    }

    /// "This is an overall goal": done automatically once every task in it is done.
    @ViewBuilder private func goalSection(_ t: TaskItem, _ edit: Bool) -> some View {
        Section {
            Toggle(isOn: Binding(get: { t.isGoal }, set: { model.update(t, ["isGoal": $0]) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This is an overall goal")
                    Text("It's done automatically once every task in it is done.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!edit)
            if t.isGoal {
                let parts = t.childIds.compactMap { model.task($0) }
                if !parts.isEmpty {
                    let done = parts.filter { model.isDone($0) }.count
                    ProgressView(value: Double(done), total: Double(parts.count)) { Text("\(done) of \(parts.count) done").font(.caption) }
                    ForEach(parts) { p in
                        NavigationLink(value: p) {
                            Label(p.title, systemImage: model.isDone(p) ? "checkmark.circle.fill" : "circle").font(.subheadline)
                        }
                    }
                }
                if edit { Button(parts.isEmpty ? "Choose the tasks it's made of" : "Change its tasks") { pickingParts = true } }
            }
            let partOf = model.tasks.filter { $0.isGoal && $0.childIds.contains(t.id) }
            ForEach(partOf) { g in
                NavigationLink(value: g) { Label("Part of goal: \(g.title)", systemImage: "target").font(.subheadline) }
            }
        }
        .listRowBackground(Color.row)
    }

    private func optionalDate(_ label: String, _ iso: String, set: @escaping (String) -> Void) -> some View {
        HStack {
            if iso.isEmpty {
                Text(label)
                Spacer()
                Button("Add") { set(Day.iso(Date())) }
            } else {
                DatePicker(label, selection: Binding(get: { Day.date(iso) ?? Date() }, set: { set(Day.iso($0)) }), displayedComponents: .date)
                Button { set("") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private func dueRow(_ t: TaskItem) -> some View {
        if t.dueDate.isEmpty {
            Button("Add a due date") { model.update(t, ["dueDate": Day.iso(Date().addingTimeInterval(7 * 86400))]) }
        } else {
            HStack {
                DatePicker("Due", selection: Binding(get: { t.due ?? Date() }, set: { model.update(t, ["dueDate": Day.iso($0)]) }), displayedComponents: .date)
                Button { model.update(t, ["dueDate": ""]) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func saveTitle(_ t: TaskItem) {
        let v = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { title = t.title } else if v != t.title { model.update(t, ["title": v]) }
    }

    private func send(_ t: TaskItem) {
        let body = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        comment = ""
        Task {
            do { try await model.addComment(t, body) } catch { comment = body; model.toast = AppModel.friendly(error) }
            sending = false
        }
    }
}

/// Pick the people on a task, searchable (works with a 40-person team).
struct PeoplePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var selected: [String]
    let onDone: ([String]) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.teammates.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { p in
                    Button {
                        if let i = selected.firstIndex(of: p.id) { selected.remove(at: i) } else { selected.append(p.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(name: p.name, photoURL: p.photoURL, size: 32)
                            Text(p.name).foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(p.id) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Owner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(selected); dismiss() }.fontWeight(.semibold) }
            }
        }
    }
}

/// Pick tasks (dependencies, a goal's parts), searchable, from this season's open board.
struct TaskPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var selected: [String]
    let exclude: String
    let onDone: ([String]) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.tasks.filter { $0.id != exclude && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
                    .sorted { (selected.contains($0.id) ? 0 : 1, $0.title) < (selected.contains($1.id) ? 0 : 1, $1.title) }) { t in
                    Button {
                        if let i = selected.firstIndex(of: t.id) { selected.remove(at: i) } else { selected.append(t.id) }
                    } label: {
                        HStack(spacing: 10) {
                            SubteamDot(color: model.subteam(t.subteamId)?.color ?? .gray)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).foregroundStyle(.primary)
                                Text([model.subteam(t.subteamId)?.name ?? "", model.columnName(t.columnId)].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(t.id) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(selected); dismiss() }.fontWeight(.semibold) }
            }
        }
    }
}
