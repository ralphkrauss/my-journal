#if os(iOS)
    import AVFoundation
    import VisionKit
    import JournalCore
    import SwiftUI
    import UIKit

    /// Scan Code: reads the pairing code a connected device shows under Settings > Devices > Add Device.
    struct ScanCodeView: View {
        let onScan: (PairingInvite) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var access = AVCaptureDevice.authorizationStatus(for: .video)
        @State private var message: String?
        @State private var found = false

        /// Whether this device can scan. Debug builds can also be given a code to read, for tests on simulators.
        static var available: Bool { DataScannerViewController.isSupported || testCode != nil }
        private static var testCode: String? {
            #if DEBUG
                ProcessInfo.processInfo.environment["JOURNAL_TEST_SCANNED_CODE"]
            #else
                nil
            #endif
        }

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                if access == .authorized && Self.testCode == nil {
                    CameraCodeReader { read($0) }.ignoresSafeArea().accessibilityLabel("Camera preview")
                } else if access == .denied || access == .restricted {
                    VStack(spacing: 16) {
                        Text("Allow camera access in Settings to scan the code.").font(.body)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }.buttonStyle(.borderedProminent)
                    }.foregroundStyle(.white).padding(32)
                }
                VStack(spacing: 0) {
                    HStack {
                        Button("Cancel") { dismiss() }.buttonStyle(.bordered).tint(.white).padding()
                        Spacer()
                    }
                    Spacer()
                    Text(message ?? "Point your camera at the code on your connected device.")
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .task {
                if let code = Self.testCode {
                    read(code)
                } else if access == .notDetermined {
                    access = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
                }
            }
        }

        private func read(_ text: String) {
            guard !found else { return }
            do {
                let invite = try PairingInvite(text: text)
                found = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                announceForAccessibility("Code found")
                onScan(invite)
                dismiss()
            } catch PairingInvite.ReadError.notInvite {
                // Some other QR code: keep looking.
            } catch {
                message = error.shown(.reading)
            }
        }
    }

    /// The camera preview, reporting the text of every QR code it recognizes.
    private struct CameraCodeReader: UIViewControllerRepresentable {
        let onRead: (String) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onRead: onRead) }

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isGuidanceEnabled: true,
                isHighlightingEnabled: true)
            scanner.delegate = context.coordinator
            try? scanner.startScanning()
            return scanner
        }

        func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
            context.coordinator.onRead = onRead
        }

        static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
            scanner.stopScanning()
        }

        @MainActor
        final class Coordinator: NSObject, DataScannerViewControllerDelegate {
            var onRead: (String) -> Void
            init(onRead: @escaping (String) -> Void) { self.onRead = onRead }

            func dataScanner(
                _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                allItems: [RecognizedItem]
            ) {
                for case .barcode(let code) in addedItems {
                    if let text = code.payloadStringValue { onRead(text) }
                }
            }
        }
    }
#endif
