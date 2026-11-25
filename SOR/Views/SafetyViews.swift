import SwiftUI

/// Report something: pick why, add a note, optionally block the person too. The Board reviews it (You › Reports).
struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: ReportTarget
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var sending = false

    private var authorName: String { model.person(target.authorUid)?.firstName ?? "this person" }
    private var whatLabel: String { ["comment": "comment", "photo": "photo", "message": "message", "task": "task"][target.kind] ?? "post" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ReportReason.allCases) { r in
                        Button { reason = r } label: {
                            HStack {
                                Text(r.rawValue).foregroundStyle(.primary)
                                Spacer()
                                if reason == r { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                } header: { Text("What's wrong with this \(whatLabel)?") }
                Section {
                    TextField("Anything the Board should know (optional)", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if !target.authorUid.isEmpty && target.authorUid != model.uid {
                    Section {
                        Toggle("Also block \(authorName)", isOn: $alsoBlock)
                    } footer: { Text("You won't see their comments, photos or Board channel messages. They aren't told.") }
                }
                Section {
                    Text("Reports go to the team's Board, who review them within a day and remove anything that breaks the team's rules. In an emergency, tell a mentor right away.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Send") { send() }.fontWeight(.semibold).disabled(reason == nil)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func send() {
        guard let reason else { return }
        sending = true
        Task {
            do {
                try await model.report(target, reason: reason, note: note)
                if alsoBlock { model.block(target.authorUid) }
                model.toast = "Thanks. The Board will review it."
                dismiss()
            } catch {
                model.toast = AppModel.friendly(error)
                sending = false
            }
        }
    }
}

/// Report and Block, for a long-press menu on someone else's comment, photo or message.
struct ReportMenuItems: View {
    @Environment(AppModel.self) private var model
    let target: ReportTarget
    let onReport: (ReportTarget) -> Void
    var body: some View {
        if target.authorUid != model.uid {
            Button { onReport(target) } label: { Label("Report", systemImage: "exclamationmark.bubble") }
            if !target.authorUid.isEmpty {
                Button(role: .destructive) { model.block(target.authorUid) } label: {
                    Label("Block \(model.person(target.authorUid)?.firstName ?? "this person")", systemImage: "hand.raised")
                }
            }
        }
    }
}

/// You › Blocked people.
struct BlockedPeopleView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if model.blockedUids.isEmpty {
                Text("You haven't blocked anyone. Long-press someone's comment, photo or message to report or block them.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.blockedUids.sorted(), id: \.self) { id in
                HStack(spacing: 12) {
                    PersonAvatar(id: id, size: 32)
                    Text(model.person(id)?.name ?? "Someone")
                    Spacer()
                    Button("Unblock") { model.unblock(id) }.buttonStyle(.bordered)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// You › Reports (admins): what people reported, to remove or dismiss.
struct ReportsView: View {
    @Environment(AppModel.self) private var model
    @State private var showDone = false

    var body: some View {
        let list = showDone ? model.reports.filter { !$0.isOpen } : model.openReports
        List {
            Picker("Show", selection: $showDone) { Text("Open").tag(false); Text("Handled").tag(true) }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
            if !model.loaded.contains("reports") && !model.demo { SkeletonRows(count: 3) }
            else if list.isEmpty {
                Text(showDone ? "Nothing handled yet." : "No open reports.").foregroundStyle(.secondary)
            }
            ForEach(list) { r in row(r) }
            Section {
                Text("Anyone on the team can report a comment, photo, Board channel message or task by long-pressing it. Remove takes it down for everyone; Dismiss keeps it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.wantReports() }
    }

    private func row(_ r: Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(r.kindLabel).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text(Date(timeIntervalSince1970: r.createdAt / 1000), format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Text(r.reason).font(.headline)
            if !r.text.isEmpty {
                Text(r.text).font(.subheadline).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.row, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("By \(r.authorName.isEmpty ? "someone" : r.authorName) · reported by \(r.reporterName.isEmpty ? "someone" : r.reporterName)")
                .font(.caption).foregroundStyle(.secondary)
            if !r.note.isEmpty { Text("“\(r.note)”").font(.caption).italic() }
            if r.isOpen {
                HStack {
                    if !r.taskId.isEmpty {
                        Button("Open task") { model.open(path: "task/\(r.taskId)") }.buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Dismiss") { model.setReport(r, status: "resolved") }.buttonStyle(.bordered)
                    if model.canRemove(r) {
                        Button("Remove", role: .destructive) { Task { await model.removeReported(r) } }.buttonStyle(.borderedProminent).tint(.red)
                    }
                }
                .font(.subheadline)
            } else {
                Text("\(r.status == "removed" ? "Removed" : "Dismissed")\(r.resolvedByName.isEmpty ? "" : " by \(r.resolvedByName)")")
                    .font(.caption.weight(.semibold)).foregroundStyle(r.status == "removed" ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
