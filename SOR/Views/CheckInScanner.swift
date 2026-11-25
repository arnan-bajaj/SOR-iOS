import SwiftUI
import VisionKit

/// Point the camera at the Monitor's QR code. It reads team.systemoverload.org/checkin/1234 and checks you in.
/// Phones without the scanner (and the Simulator) type the four digits instead.
struct CheckInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @FocusState private var typing: Bool

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if canScan {
                    QRScanner { found in submit(found) }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15)))
                        .frame(maxHeight: 380)
                    Text("Point your camera at the QR code on the meeting-room Monitor.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("or type the code").font(.caption).foregroundStyle(.tertiary)
                } else {
                    Text("Type the four digits under the QR code on the meeting-room Monitor.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                HStack {
                    TextField("1234", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.center)
                        .focused($typing)
                        .frame(height: 54)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: code) { _, v in if v.filter(\.isNumber).count == 4 { submit(v) } }
                    if busy { ProgressView().padding(.leading, 8) }
                }
                Text("On time for the first 25 minutes of a meeting, Partial after that.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .background(Color.sheet)
            .navigationTitle("Check in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { if !canScan { typing = true } }
        }
    }

    private func submit(_ text: String) {
        guard !busy else { return }
        // A scanned link (…/checkin/1234) or the digits themselves
        let digits = text.range(of: #"checkin/(\d{4})"#, options: .regularExpression).map { String(text[$0].suffix(4)) } ?? text.filter(\.isNumber)
        guard digits.count == 4 else { return }
        busy = true
        Task {
            await model.checkIn(code: digits)
            busy = false
            if model.toast?.hasPrefix("Checked in") == true || model.toast == "You're already checked in." { dismiss() } else { code = "" }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var last = ""
        init(_ f: @escaping (String) -> Void) { onFound = f }
        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items {
                guard let s = b.payloadStringValue, s != last else { continue }
                last = s
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFound(s)
            }
        }
    }
}

/// Where a link or notification goes, shown over whichever tab you're on.
struct LinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let link: AppLink

    var body: some View {
        switch link {
        case .meeting(let id):
            if let e = model.events.first(where: { $0.id == id }) { MeetingDetailView(event: e) }
            else { wrap { WebPageView(title: "Signups", path: "signups/\(id)") } }
        case .task(let id):
            wrap { TaskDetailView(taskId: id) }
        case .action(let id):
            let a = model.actionItems.first { $0.id == id } ?? model.privateActionItems.first { $0.id == id }
            wrap { ActionItemsView(boardRoom: a?.confidential ?? false, startTrack: Track(rawValue: a?.track ?? "") ?? .board) }
        case .web(let path):
            wrap { WebPageView(title: "Team Board", path: path) }
        }
    }

    private func wrap<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        NavigationStack {
            v().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
                .navigationDestination(for: WebLink.self) { WebPageView(title: $0.title, path: $0.path) }
        }
    }
}
