import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var privacy: URL?
    @State private var otherSignIn = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer()
                Image("Logo").resizable().scaledToFit().frame(width: 150, height: 150).clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                Text("SOR Team Board").font(.largeTitle.weight(.bold)).padding(.top, 28)
                Text("Tasks, meetings and check-ins for FRC 6059 System Overload.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 32)
                Spacer()
                Button {
                    busy = true
                    Task { await model.signIn(); busy = false }
                } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(.black) } else { GoogleMark() }
                        Text("Continue with Google").font(.headline)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(busy)
                .padding(.horizontal, 24)
                Text("Use the Google account you use for the team. A Board member approves new people.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 14).padding(.horizontal, 32)
                HStack(spacing: 18) {
                    Button("Other sign-in") { otherSignIn = true }
                    Button("Look around the demo") { model.startDemo() }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 14)
                Button("Privacy Policy") { privacy = AppModel.site.appending(path: "privacy") }
                    .font(.footnote).padding(.top, 10).padding(.bottom, 24)
            }
        }
        .sheet(item: $privacy) { SafariView(url: $0).ignoresSafeArea() }
        .sheet(isPresented: $otherSignIn) { EmailSignInView() }
    }
}

/// The four-colour G, drawn so there's no image asset to license.
struct GoogleMark: View {
    var body: some View {
        Text("G").font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Sign in with an email and password instead of Google, for accounts an admin made in Firebase (Authentication ›
/// Users), like the App Store reviewer's. A new account still waits for a Board member's approval.
struct EmailSignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var field: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($field, equals: 0).submitLabel(.next)
                        .onSubmit { field = 1 }
                    SecureField("Password", text: $password).textContentType(.password).focused($field, equals: 1).submitLabel(.go)
                        .onSubmit(go)
                } footer: {
                    Text(error ?? "For accounts the team set up with an email and password. Team members usually use Continue with Google.")
                        .foregroundStyle(error == nil ? Color.secondary : Color.red)
                }
                .listRowBackground(Color.row)
                Section {
                    Button(action: go) {
                        HStack { Text("Sign in").fontWeight(.semibold); if busy { Spacer(); ProgressView() } }
                    }
                    .disabled(email.isEmpty || password.isEmpty || busy)
                }
                .listRowBackground(Color.row)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Other sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { field = 0 }
        }
        .presentationDetents([.medium, .large])
    }

    private func go() {
        guard !email.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            error = await model.signIn(email: email, password: password)
            busy = false
            if error == nil { dismiss() }
        }
    }
}
