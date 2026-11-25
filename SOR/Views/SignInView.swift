import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var privacy: URL?

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
                Button("Privacy Policy") { privacy = AppModel.site.appending(path: "privacy") }
                    .font(.footnote).padding(.top, 10).padding(.bottom, 24)
            }
        }
        .sheet(item: $privacy) { SafariView(url: $0).ignoresSafeArea() }
    }
}

/// The four-colour G, drawn so there's no image asset to license.
struct GoogleMark: View {
    var body: some View {
        Text("G").font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
