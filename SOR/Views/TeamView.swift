import SwiftUI

/// Team: everyone on the board, new people waiting for approval (admins approve them), and roles.
/// Leadership positions, subteams and seasons are edited on the website (linked at the bottom).
struct TeamView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var people: [Person] {
        model.users.filter { $0.role != .pending }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.role.rank, $1.name) > ($1.role.rank, $0.name) }
    }

    var body: some View {
        List {
            if model.isAdmin && !model.pendingPeople.isEmpty {
                Section("Waiting for approval") {
                    ForEach(model.pendingPeople) { p in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Avatar(name: p.name, photoURL: p.photoURL, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.body.weight(.medium))
                                    Text("\(p.memberTypeLabel) · \(p.email)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button("Decline", role: .destructive) { model.decline(p) }.buttonStyle(.bordered)
                                Spacer()
                                Button("Approve as \(model.approveRole(p).label)") { model.setRole(p, model.approveRole(p)) }.buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.card)
            }
            Section("\(people.count) people") {
                ForEach(people) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, photoURL: p.photoURL, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            FlowLayout(spacing: 8, lineSpacing: 2) {
                                ForEach(p.subteamIds.compactMap { model.subteam($0) }) { s in
                                    HStack(spacing: 4) { SubteamDot(color: s.color, size: 7); Text(s.name) }
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isAdmin && p.id != model.uid {
                            Menu {
                                ForEach([Role.admin, .lead, .member, .viewer], id: \.self) { r in
                                    Button { model.setRole(p, r) } label: { if r == p.role { Label(r.label, systemImage: "checkmark") } else { Text(r.label) } }
                                }
                            } label: { Pill(text: p.role.label, tint: p.role == .admin ? .accentColor : .secondary) }
                        } else {
                            Pill(text: p.role.label, tint: p.role == .admin ? .accentColor : .secondary)
                        }
                    }
                }
            }
            .listRowBackground(Color.card)
            Section {
                NavigationLink(value: WebLink(title: "Team", path: "team")) { Label("Leadership, subteams and seasons", systemImage: "person.3") }
            }
            .listRowBackground(Color.card)
        }
        .searchable(text: $query)
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .navigationTitle("Team")
    }
}
