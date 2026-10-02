import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Reads the chosen picture; called off the picker so large photos don't hold up the interface.
typealias ImageLoad = @Sendable () async throws -> Data

/// Presents the picker for Insert Image: the photo library, the camera, or Files (the only choice on the Mac).
struct ImagePickerPresenter: View {
    let session: ImageInsertionSession
    let source: EditorActions.ImageSource
    @Binding var isPresented: Bool
    let receive: (ImageInsertionSession, Result<ImageLoad, Error>) -> Void
    @State private var photo: PhotosPickerItem?

    var body: some View {
        let anchor = Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        #if os(iOS)
            switch source {
            case .photos:
                anchor.photosPicker(isPresented: $isPresented, selection: $photo, matching: .images)
                    .onValueChange(of: photo) { item in
                        guard let item else { return }
                        photo = nil
                        receive(session, .success { try await Self.data(from: item) })
                    }
            case .camera where CameraPicker.isDenied:
                // With access turned off the camera would open black; say where to turn it on instead.
                anchor.alert("Camera Access Is Off", isPresented: $isPresented) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Allow camera access in Settings to take photos.")
                }
            case .camera:
                anchor.fullScreenCover(isPresented: $isPresented) {
                    CameraPicker { data in
                        isPresented = false
                        if let data { receive(session, .success { data }) }
                    }.ignoresSafeArea()
                }
            case .files:
                files(anchor)
            }
        #else
            files(anchor)
        #endif
    }
    private func files(_ anchor: some View) -> some View {
        anchor.fileImporter(isPresented: $isPresented, allowedContentTypes: [.image]) { [session] result in
            receive(session, result.map { url -> ImageLoad in { try Self.data(from: url) } })
        }
    }
    private nonisolated static func data(from url: URL) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
    private nonisolated static func data(from item: PhotosPickerItem) async throws -> Data {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }
}

#if os(iOS)
    /// The system camera. Hidden from the Insert Image menu on devices without one.
    struct CameraPicker: UIViewControllerRepresentable {
        /// A camera blocked by Screen Time or device management is treated as absent; Settings can't change that here.
        static var isAvailable: Bool {
            UIImagePickerController.isSourceTypeAvailable(.camera)
                && AVCaptureDevice.authorizationStatus(for: .video) != .restricted
        }
        static var isDenied: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .denied }
        let finish: (Data?) -> Void
        func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }
        func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
        @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let finish: (Data?) -> Void
            init(finish: @escaping (Data?) -> Void) { self.finish = finish }
            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                let image = info[.originalImage] as? UIImage
                finish(image?.jpegData(compressionQuality: 0.9))
            }
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }
        }
    }
#endif
