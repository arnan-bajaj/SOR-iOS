import SwiftUI

/// The questions everyone answers once (mod-app QUESTIONS), then waiting for a Board member's approval.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var female: Bool?
    @State private var side = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 18) {
                ProgressView(value: Double(step + 1), total: 3).tint(.accentColor).padding(.top, 12)
                Spacer()
                switch step {
                case 0:
                    question("Do you identify as female?",
                             why: "Every in-person meeting needs the right adults there, so the team keeps track of this. Only you and team leads can see your answer.",
                             options: [("yes", "Yes"), ("no", "No")]) { female = $0 == "yes"; step = 1 }
                case 1:
                    question("Are you a student or a parent?", options: [("student", "Student"), ("adult", "Parent or mentor")]) { side = $0; step = 2 }
                default:
                    question(side == "adult" ? "How do you help the team?" : "What's your role on the team?",
                             options: side == "adult" ? [("mentor", "Mentor"), ("parent", "Parent volunteer")] : [("student", "Student"), ("lead", "Lead"), ("board", "Board")]) { type in
                        save(type)
                    }
                }
                Spacer()
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Skip for now") { model.skipAnswers() }
                }
                if step > 0 { Button("Back") { step -= 1 }.disabled(saving) }
            }
            .padding(24)
        }
    }

    private func question(_ title: String, why: String? = nil, options: [(String, String)], pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.largeTitle.weight(.bold))
            if let why { Text(why).foregroundStyle(.secondary) }
            VStack(spacing: 10) {
                ForEach(options, id: \.0) { value, label in
                    Button { pick(value) } label: {
                        HStack {
                            Text(label).font(.headline)
                            Spacer()
                            if saving && step == 2 { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                        }
                        .padding(18)
                        .glass(18)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
            }
            .padding(.top, 8)
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        .id(step)
    }

    private func save(_ type: String) {
        saving = true
        error = nil
        Task {
            do { try await model.saveAnswers(female: female ?? false, memberType: type) } catch {
                self.error = "Couldn't save your answers: \(AppModel.friendly(error))"
            }
            saving = false
        }
    }
}

struct PendingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 16) {
                Avatar(name: model.profile?.name ?? "", photoURL: model.authPhoto, size: 96)
                Text("Almost in, \(model.profile?.firstName ?? "")").font(.title.weight(.bold))
                HStack(spacing: 8) {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("A Board member needs to approve **\(model.authEmail)**. The app opens by itself as soon as they do.")
                }
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("Signed up as **\(model.profile?.memberTypeLabel ?? "a team member")**").font(.footnote).foregroundStyle(.secondary)
                Button("Use a different account") { model.signOut() }.buttonStyle(.bordered).padding(.top, 12)
            }
            .padding(32)
        }
    }
}
