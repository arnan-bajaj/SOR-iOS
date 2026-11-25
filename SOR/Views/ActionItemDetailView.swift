import SwiftUI

/// One action item, like the website's action item sheet: words, who, due date, Slack reminders, done,
/// make it a task, copy its link, delete.
struct ActionItemDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let itemId: String
    let confidential: Bool
    @State private var text = ""
    @State private var picking = false
    @State private var promoting = false
    @FocusState private var editing: Bool

    private var item: ActionItem? {
        (confidential ? model.privateActionItems : model.actionItems).first { $0.id == itemId }
    }

    var body: some View {
        if let a = item { content(a) } else {
            ContentUnavailableView("This action item is gone", systemImage: "questionmark.square.dashed")
        }
    }

    private func content(_ a: ActionItem) -> some View {
        let edit = model.canChange(a)
        return Form {
            Section {
                TextField("What needs doing?", text: $text, axis: .vertical).font(.title3.weight(.semibold)).focused($editing).disabled(!edit)
                Toggle(isOn: Binding(get: { a.done }, set: { model.setDone(a, $0) })) { Label("Done", systemImage: "checkmark.circle") }.disabled(!edit)
            }
            .listRowBackground(Color.row)
            Section {
                if !confidential {
                    Picker("Meeting", selection: Binding(get: { Track(rawValue: a.track) ?? .board }, set: { model.patch(a, ["track": $0.rawValue]) })) {
                        ForEach(Track.allCases) { Text($0.label).tag($0) }
                    }
                }
                Button { picking = true } label: {
                    HStack {
                        Text("Who").foregroundStyle(.primary)
                        Spacer()
                        if a.ownerUids.isEmpty { Text("Nobody").foregroundStyle(.secondary) } else {
                            AvatarStack(ids: a.ownerUids, size: 20)
                            Text(a.ownerUids.compactMap { model.person($0)?.firstName }.joined(separator: ", ")).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                if a.dueDate.isEmpty {
                    Button("Add a due date") { model.patch(a, ["dueDate": Day.iso(Date().addingTimeInterval(7 * 86400))]) }
                } else {
                    HStack {
                        DatePicker("Due", selection: Binding(get: { Day.date(a.dueDate) ?? Date() }, set: { model.patch(a, ["dueDate": Day.iso($0)]) }), displayedComponents: .date)
                        Button { model.patch(a, ["dueDate": ""]) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
                LabeledContent("Assigned", value: Day.date(a.day)?.formatted(.dateTime.weekday(.wide).month().day()) ?? a.day)
            }
            .disabled(!edit)
            .listRowBackground(Color.row)
            if !confidential {
                Section {
                    ReminderChips(on: a.reminders) { model.patch(a, ["reminders": $0]) }.disabled(!edit || a.dueDate.isEmpty)
                } header: { Text("Remind in Slack") } footer: {
                    Text(a.dueDate.isEmpty ? "Give it a due date to get reminders." : "Posted in the \(Track(rawValue: a.track)?.label ?? "meeting")'s Slack channel when that much of the time from the meeting to the due date has gone by. The people on it get a push too.")
                }
                .listRowBackground(Color.row)
            }
            Section {
                if !a.promotedTaskId.isEmpty, let t = model.task(a.promotedTaskId) {
                    NavigationLink(value: t) { Label("Open its task: \(t.title)", systemImage: "rectangle.on.rectangle") }
                } else if model.canEdit && !confidential {
                    Button {
                        promoting = true
                        Task {
                            do { _ = try await model.promote(a); model.toast = "Added to the board" } catch { model.toast = AppModel.friendly(error) }
                            promoting = false
                        }
                    } label: { HStack { Label("Make it a task", systemImage: "arrow.up.forward.square"); if promoting { Spacer(); ProgressView() } } }
                }
                ShareLink(item: AppModel.site.appending(path: "action/\(a.id)")) { Label("Share link", systemImage: "link") }
                if model.canRemove(a) {
                    Button(role: .destructive) { model.deleteItem(a); dismiss() } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .listRowBackground(Color.row)
        }
        .scrollContentBackground(.hidden)
        .appBackground(Brand.teal)
        .navigationTitle(confidential ? "Confidential item" : "Action item")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
        .sheet(isPresented: $picking) { PeoplePicker(selected: a.ownerUids) { model.patch(a, ["ownerUids": $0, "ownerUid": ""]) } }
        .onAppear { text = a.text }
        .onChange(of: editing) { was, _ in
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if was == true || !editing, !v.isEmpty, v != a.text { model.patch(a, ["text": v]) }
        }
        .onDisappear {
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty, v != a.text, edit { model.patch(a, ["text": v]) }
        }
    }
}

/// 25 / 50 / 75 / 90% Slack reminder chips (REMINDER_STEPS in index.html and the bot).
struct ReminderChips: View {
    let on: [Int]
    let set: ([Int]) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach([25, 50, 75, 90], id: \.self) { p in
                let active = on.contains(p)
                Button {
                    set(active ? on.filter { $0 != p } : (on + [p]).sorted())
                } label: {
                    Text("\(p)%").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(Brand.wash(Brand.blue)) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: Capsule())
                        .foregroundStyle(active ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Action Items › Reminders (Board and Build Committee): a note the bot posts in that meeting's Slack channel on a date.
struct TeamRemindersView: View {
    @Environment(AppModel.self) private var model
    let track: Track
    @State private var text = ""
    @State private var when = Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
    @State private var saving = false

    var body: some View {
        let now = Date().timeIntervalSince1970 * 1000
        let mine = model.teamReminders.filter { $0.track == track.rawValue }
        let upcoming = mine.filter { $0.sentAt == 0 && $0.sendAt > now - 7 * 86_400_000 }.sorted { $0.sendAt < $1.sendAt }
        let sent = mine.filter { $0.sentAt > 0 }.sorted { $0.sendAt > $1.sendAt }.prefix(10)
        let channel = model.reminderChannel(track)
        List {
            if model.canEdit {
                Section {
                    TextField("Remind us to…", text: $text, axis: .vertical)
                    DatePicker("Post it", selection: $when, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Button {
                        saving = true
                        Task {
                            do {
                                try await model.addTeamReminder(text: text, track: track, at: when)
                                model.toast = "The bot will post it \(when.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))."
                                text = ""
                            } catch { model.toast = error is AppError ? error.localizedDescription : AppModel.friendly(error) }
                            saving = false
                        }
                    } label: { HStack { Text("Add reminder").fontWeight(.semibold); if saving { Spacer(); ProgressView() } } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                } header: { Text("New") } footer: {
                    Text(channel.isEmpty ? "\(track.label) has no Slack channel yet, so reminders can't go out. An admin sets one on Team › Subteams."
                                         : "Posted once in \(channel.hasPrefix("C") && channel.count > 8 ? "its private Slack channel" : "#\(channel)") at that time.")
                }
                .listRowBackground(Color.row)
            }
            Section("Coming up · \(upcoming.count)") {
                if upcoming.isEmpty { Text("Nothing scheduled.").foregroundStyle(.secondary) }
                ForEach(upcoming) { r in reminderRow(r) }
            }
            .listRowBackground(Color.row)
            if !sent.isEmpty {
                Section("Sent") { ForEach(Array(sent)) { r in reminderRow(r).opacity(0.6) } }.listRowBackground(Color.row)
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { model.wantTeamReminders() }
    }

    private func reminderRow(_ r: TeamReminder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.text)
            HStack(spacing: 6) {
                Image(systemName: r.sentAt > 0 ? "checkmark.circle.fill" : "clock")
                Text(Date(timeIntervalSince1970: r.sendAt / 1000).formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                if let p = model.person(r.createdBy) { Text("· \(p.firstName)") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions {
            if model.isLead || r.createdBy == model.uid { Button("Delete", role: .destructive) { model.deleteTeamReminder(r) } }
        }
    }
}
