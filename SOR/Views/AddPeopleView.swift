import SwiftUI

/// Leads put anyone on the roster on a shift, or take them off (the website's "Add someone").
struct AddPeopleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shift: Shift
    @State private var query = ""
    @State private var busy: Set<String> = []

    var body: some View {
        let everyone = model.rosterPeople.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let groups: [(String, String)] = [("student", "Students"), ("parent", "Parents"), ("mentor", "Mentors")]
        NavigationStack {
            List {
                if !model.loaded.contains("roster") && !model.demo {
                    SkeletonRows(count: 5).listRowBackground(Color.clear)
                } else if everyone.isEmpty {
                    Text(query.isEmpty ? "The roster is empty. Leads add people on the website's Attendance › Roster." : "Nobody by that name on the roster.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.0) { kind, title in
                    let rows = everyone.filter { $0.kind == kind || (kind == "student" && !["parent", "mentor"].contains($0.kind)) }
                    if !rows.isEmpty {
                        Section(title) {
                            ForEach(rows) { w in row(w) }
                        }
                        .listRowBackground(Color.row)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the roster")
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Add someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .onAppear { model.wantRoster() }
        }
    }

    private func row(_ w: AppModel.Who) -> some View {
        let on = model.signup(of: w, at: shift.id)
        return Button {
            busy.insert(w.key)
            Task {
                if let on { model.removeSignup(on) } else { await model.addToShift(w, shift) }
                busy.remove(w.key)
            }
        } label: {
            HStack(spacing: 12) {
                if w.uid.isEmpty { Avatar(name: w.name, photoURL: "", size: 32) } else { PersonAvatar(id: w.uid, size: 32) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(w.name).foregroundStyle(.primary)
                    if w.uid.isEmpty { Text("No board account").font(.caption).foregroundStyle(.secondary) }
                }
                if w.femaleAdult { Text("F").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                Spacer()
                if busy.contains(w.key) { ProgressView() }
                else { Image(systemName: on == nil ? "circle" : "checkmark.circle.fill").font(.title3).foregroundStyle(on == nil ? Color.secondary : Color.green) }
            }
        }
        .disabled(busy.contains(w.key))
    }
}
