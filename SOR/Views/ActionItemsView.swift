import SwiftUI

/// Action Items: Board, Build Committee and Operations. Items are handed out at meetings, so they're grouped by the
/// meeting day they were assigned at, newest first (never by Mon–Sun weeks).
struct ActionItemsView: View {
    @Environment(AppModel.self) private var model
    var boardRoom = false
    @State private var track: Track = .board
    @State private var adding = false
    @State private var showDone = false

    private var list: [ActionItem] { boardRoom ? model.boardRoomItems : model.items(track: track) }

    var body: some View {
        let items = list.filter { showDone || !$0.done }
        let groups = Dictionary(grouping: items, by: \.day)
        List {
            if !boardRoom {
                Picker("Meeting", selection: $track) { ForEach(Track.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else {
                Text("Confidential: only the Board and lead mentors can see this.").font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if !model.loaded.contains(boardRoom ? "privateActionItems" : "actionItems") && !model.demo {
                SkeletonRows(count: 4).listRowBackground(Color.clear)
            } else if items.isEmpty {
                Text(list.isEmpty ? "No action items yet this season." : "Everything's done.").foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                Section(heading(day)) {
                    ForEach(groups[day]!.sorted { !$0.done && $1.done || ($0.done == $1.done && $0.createdAt < $1.createdAt) }) { a in
                        ActionItemRow(item: a)
                            .swipeActions {
                                if model.canRemove(a) { Button("Delete", role: .destructive) { model.deleteItem(a) } }
                            }
                    }
                }
                .listRowBackground(Color.card)
            }
            Section {
                NavigationLink(value: WebLink(title: boardRoom ? "Board Room" : "Action Items",
                                              path: boardRoom ? "boardroom" : "actions/\(track.rawValue)")) {
                    Label(boardRoom ? "Board channel and agendas" : "Agenda documents and reminders", systemImage: "doc.text")
                }
            }
            .listRowBackground(Color.card)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .navigationTitle(boardRoom ? "Board Room" : "Action Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { Toggle("Show done", isOn: $showDone) } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
            if boardRoom ? model.isBoardMember : model.canEdit {
                ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } }
            }
        }
        .sheet(isPresented: $adding) { NewActionItemView(track: boardRoom ? .board : track, confidential: boardRoom) }
    }

    private func heading(_ day: String) -> String {
        guard let d = Day.date(day) else { return day }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

struct ActionItemRow: View {
    @Environment(AppModel.self) private var model
    let item: ActionItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.setDone(item, !item.done) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(item.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!model.canChange(item))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                HStack(spacing: 6) {
                    if !item.ownerUids.isEmpty {
                        AvatarStack(ids: item.ownerUids, size: 18)
                        Text(item.ownerUids.compactMap { model.person($0)?.firstName }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                    DuePill(iso: item.dueDate, done: item.done)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct NewActionItemView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var track: Track
    let confidential: Bool
    @State private var text = ""
    @State private var owners: [String] = []
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(7 * 86400)
    @State private var saving = false
    @State private var picking = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs doing?", text: $text, axis: .vertical).font(.title3).focused($focused)
                if !confidential {
                    Picker("Meeting", selection: $track) { ForEach(Track.allCases) { Text($0.label).tag($0) } }
                }
                Button { picking = true } label: {
                    HStack {
                        Text("Who").foregroundStyle(.primary)
                        Spacer()
                        Text(owners.isEmpty ? "You" : owners.compactMap { model.person($0)?.firstName }.joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                }
                Toggle("Due date", isOn: $hasDue.animation())
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                Section {
                    Text("It's filed under today's meeting.\(confidential ? " Confidential: only the Board and lead mentors see it." : "")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.sheet)
            .navigationTitle(confidential ? "Confidential action item" : "New action item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Add") { save() }.fontWeight(.semibold).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .sheet(isPresented: $picking) { PeoplePicker(selected: owners) { owners = $0 } }
            .onAppear { focused = true }
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                try await model.addActionItem(text: text, track: track, owners: owners, dueDate: hasDue ? Day.iso(due) : "", confidential: confidential)
                model.toast = "Action item added"
                dismiss()
            } catch {
                model.toast = AppModel.friendly(error)
                saving = false
            }
        }
    }
}

/// Archived tasks from this season, with Restore (the website's Archive page).
struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if model.archivedTasks.isEmpty { Text("Nothing archived this season.").foregroundStyle(.secondary) }
            ForEach(model.archivedTasks) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title)
                        if let s = model.subteam(t.subteamId) {
                            HStack(spacing: 5) { SubteamDot(color: s.color, size: 7); Text(s.name) }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if model.canEdit {
                        Button("Restore") { model.unarchive(t); model.toast = "Restored “\(t.title)”" }.buttonStyle(.bordered)
                    }
                }
            }
            .listRowBackground(Color.card)
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
    }
}
