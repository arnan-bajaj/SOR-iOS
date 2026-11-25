import SwiftUI

struct NewTaskView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var subteamId: String?
    var columnId: String?
    /// Set when the form is the Create tab rather than a sheet: Cancel and Add call it (back to the last tab) instead of dismissing.
    var onDone: (() -> Void)?

    @State private var title = ""
    @State private var notes = ""
    @State private var board = ""
    @State private var owners: [String] = []
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(7 * 86400)
    @State private var priority = Priority.med
    @State private var saving = false
    @State private var pickingPeople = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title, axis: .vertical).font(.title3).focused($titleFocused)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...)
                }
                Section {
                    Picker("Board", selection: $board) {
                        ForEach(model.boards) { s in
                            HStack { SubteamDot(color: s.color); Text(s.name) }.tag(s.id)
                        }
                    }
                    Button { pickingPeople = true } label: {
                        HStack {
                            Text("Owner").foregroundStyle(.primary)
                            Spacer()
                            Text(owners.isEmpty ? "Nobody yet" : owners.compactMap { model.person($0)?.firstName }.joined(separator: ", ")).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                    Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    Text("Slack reminds the owner when 90% of the time is up, like tasks made on the website.").font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Add") { save() }.fontWeight(.semibold)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || board.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $pickingPeople) { PeoplePicker(selected: owners) { owners = $0 } }
            .onAppear {
                if board.isEmpty {
                    let mine = model.profile?.subteamIds.first { id in model.boards.contains { $0.id == id } }
                    board = (subteamId.flatMap { id in model.boards.first { $0.id == id }?.id }) ?? mine ?? model.boards.first?.id ?? ""
                }
                if owners.isEmpty { owners = [model.uid] }
                titleFocused = true
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func save() {
        saving = true
        let col = columnId.flatMap { id in model.columns(for: board).contains { $0.id == id } ? id : nil }
        Task {
            do {
                try await model.createTask(title: title, description: notes, subteamId: board, columnId: col, assignees: owners,
                                           dueDate: hasDue ? Day.iso(due) : "", priority: priority)
                model.toast = "Task added"
                saving = false
                finish()
            } catch {
                model.toast = AppModel.friendly(error)
                saving = false
            }
        }
    }
}
