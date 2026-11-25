import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = "system"
    @State private var web: URL?
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Avatar(name: model.profile?.name ?? "", photoURL: model.authPhoto, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.profile?.name ?? "").font(.title3.weight(.semibold))
                            Text(model.authEmail).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Pill(text: model.role.label, tint: .accentColor)
                                if let p = model.profile, !p.memberType.isEmpty { Pill(text: p.memberTypeLabel) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    if let ids = model.profile?.subteamIds, !ids.isEmpty {
                        FlowLayout(spacing: 12) {
                            ForEach(ids.compactMap { model.subteam($0) }) { s in
                                HStack(spacing: 5) { SubteamDot(color: s.color, size: 8); Text(s.name) }.font(.subheadline)
                            }
                        }
                    }
                }

                Section {
                    Button { model.showHelper = true } label: { RowLabel(title: "Ask the helper", systemImage: "sparkles", color: Brand.violet) }
                        .foregroundStyle(.primary)
                    NavigationLink(value: YouPage.notifications) { RowLabel(title: "Notifications", systemImage: "bell.badge.fill", color: .red) }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Match iPhone").tag("system")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Team") {
                    NavigationLink(value: YouPage.team) {
                        HStack {
                            RowLabel(title: "Team", systemImage: "person.3.fill", color: Brand.blue)
                            if model.isAdmin && !model.pendingPeople.isEmpty {
                                Spacer()
                                Text("\(model.pendingPeople.count) waiting").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3).background(.red, in: Capsule())
                            }
                        }
                    }
                    if model.canSeeBoardRoom {
                        NavigationLink(value: YouPage.boardRoom) { RowLabel(title: "Board Room", systemImage: "lock.fill", color: Brand.red) }
                    }
                    NavigationLink(value: YouPage.analytics) { RowLabel(title: "Analytics", systemImage: "chart.bar.xaxis", color: Brand.teal) }
                    NavigationLink(value: YouPage.archive) { RowLabel(title: "Archive", systemImage: "archivebox.fill", color: .gray) }
                    if model.isHelperReviewer {
                        NavigationLink(value: YouPage.helperChats) { RowLabel(title: "Helper chats", systemImage: "sparkles", color: Brand.violet) }
                    }
                    if model.isAdmin {
                        NavigationLink(value: YouPage.reports) {
                            HStack {
                                RowLabel(title: "Reports", systemImage: "exclamationmark.bubble.fill", color: .orange)
                                if !model.openReports.isEmpty {
                                    Spacer()
                                    Text("\(model.openReports.count) open").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3).background(.orange, in: Capsule())
                                }
                            }
                        }
                    }
                    if model.isLead {
                        NavigationLink(value: YouPage.signupRecords) { RowLabel(title: "Signup records", systemImage: "doc.text.fill", color: Brand.amber) }
                    }
                }

                Section {
                    NavigationLink(value: YouPage.blocked) { RowLabel(title: "Blocked people", systemImage: "hand.raised.fill", color: .gray) }
                } header: { Text("Safety") } footer: {
                    Text("Long-press a comment, photo or message to report it or block its author. The Board reviews every report.")
                }

                Section("About") {
                    Button { web = AppModel.site.appending(path: "privacy") } label: { RowLabel(title: "Privacy Policy", systemImage: "hand.raised.fill", color: Brand.blue) }
                    Button { web = AppModel.site.appending(path: "support") } label: { RowLabel(title: "Help and support", systemImage: "questionmark.circle.fill", color: Brand.teal) }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }

                Section {
                    Button(model.demo ? "Leave the demo" : "Sign out") { model.signOut() }
                    if !model.demo {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        HStack { Text("Delete my account"); if deleting { Spacer(); ProgressView() } }
                    }
                    .disabled(deleting)
                    }
                } footer: {
                    Text("Deleting removes your profile, your private answers and your sign-in. Tasks, comments and attendance you were part of stay with the team's records.")
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("You")
            .navigationDestination(for: WebLink.self) { WebPageView(title: $0.title, path: $0.path) }
            .navigationDestination(for: YouPage.self) { page in
                switch page {
                case .team: TeamView()
                case .boardRoom: BoardRoomView()
                case .analytics: AnalyticsView()
                case .archive: ArchiveView()
                case .helperChats: HelperChatsView()
                case .signupRecords: SignupRecordsView()
                case .notifications: NotificationSettingsView()
                case .reports: ReportsView()
                case .blocked: BlockedPeopleView()
                }
            }
            .sheet(item: $web) { SafariView(url: $0).ignoresSafeArea() }
            .onAppear { model.wantReports() }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete my account", role: .destructive) { delete() }
            } message: {
                Text("Google will ask you to sign in once more to confirm. You can join again later, but a Board member will need to approve you again.")
            }
        }
    }

    private func delete() {
        deleting = true
        Task {
            do { try await model.deleteAccount() } catch {
                model.toast = "Couldn't delete your account: \(AppModel.friendly(error))"
            }
            deleting = false
        }
    }
}

enum YouPage: Hashable { case team, boardRoom, notifications, analytics, archive, helperChats, signupRecords, reports, blocked }

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            if !model.pushAllowed {
                Section {
                    Text("Notifications are off for this app.")
                    Button("Turn them on in Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
                .listRowBackground(Color.row)
            }
            Section {
                ForEach(PushKind.allCases.filter { $0 != .team || model.isAdmin || model.role == .pending }) { k in
                    Toggle(isOn: Binding(get: { model.pushOn(k) }, set: { model.setPush(k, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.label)
                            Text(k.hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Nothing is sent between 9 pm and 8 am except quietly. Slack keeps sending what it sends now.")
            }
            .listRowBackground(Color.row)
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
