import SwiftUI

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    let taskId: String

    @State private var title = ""
    @State private var notes = ""
    @State private var newItem = ""
    @State private var comment = ""
    @State private var comments: [Comment] = []
    @State private var stopComments: (() -> Void)?
    @State private var pickingPeople = false
    @State private var sending = false
    @FocusState private var focus: Field?
    enum Field { case title, notes, item, comment }

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
                if comments.isEmpty { Text("No comments yet.").foregroundStyle(.secondary) }
                ForEach(comments) { c in
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
                Link(destination: AppModel.site.appending(path: "task/\(t.id)")) {
                    Label("Open on the website", systemImage: "safari")
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
        .sheet(isPresented: $pickingPeople) {
            PeoplePicker(selected: t.assigneeUids) { model.update(t, ["assigneeUids": $0]) }
        }
        .onAppear {
            title = t.title
            notes = t.description
            stopComments = model.comments(t.id) { comments = $0 }
        }
        .onDisappear { stopComments?() }
        .onChange(of: focus) { old, _ in
            // Save a field when you leave it, like the website's editor.
            if old == .title { saveTitle(t) }
            if old == .notes, notes != t.description { model.update(t, ["description": notes]) }
        }
        .onChange(of: t.title) { _, new in if focus != .title { title = new } }
        .onChange(of: t.description) { _, new in if focus != .notes { notes = new } }
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
