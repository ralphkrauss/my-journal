#if os(iOS)
    import JournalCore
    import LinkPresentation
    import Photos
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    /// Long press on a picture, its VoiceOver actions, and copying a selected picture on iPhone and iPad
    /// (docs/design/image-actions-ios-2026-10-03.md).
    extension NativeEditor.Coordinator {
        enum ImageAction: CaseIterable {
            case copy, share, save, describe, delete

            var title: String {
                switch self {
                case .copy: return "Copy"
                case .share: return "Share…"
                case .save: return "Save to Photos"
                case .describe: return "Image Descriptions…"
                case .delete: return "Delete"
                }
            }
            /// VoiceOver's name for the action, without the ellipsis.
            var spoken: String {
                switch self {
                case .share: return "Share"
                case .describe: return "Image Descriptions"
                default: return title
                }
            }
            var symbol: String {
                switch self {
                case .copy: return "doc.on.doc"
                case .share: return "square.and.arrow.up"
                case .save: return "square.and.arrow.down"
                case .describe: return "text.below.photo"
                case .delete: return "trash"
                }
            }
        }

        /// What can be done with `item` now: the original's actions only while the picture is shown, the entry's only
        /// while it can be edited.
        func imageActions(for item: ImageItem) -> [ImageAction] {
            guard let support = parent.imageActions else { return [] }
            var result: [ImageAction] = []
            if let id = item.attachmentID, parent.images[id] != nil { result += [.copy, .share, .save] }
            if parent.editable {
                if support.describe != nil { result.append(.describe) }
                result.append(.delete)
            }
            return result
        }

        func imageMenu(for item: ImageItem) -> UIMenu? {
            let actions = imageActions(for: item)
            guard !actions.isEmpty else { return nil }
            func action(_ kind: ImageAction) -> UIAction {
                UIAction(
                    title: kind.title, image: UIImage(systemName: kind.symbol),
                    attributes: kind == .delete ? .destructive : []
                ) { [weak self] _ in self?.perform(kind, on: item) }
            }
            let main = actions.filter { $0 != .delete }.map(action)
            let destructive =
                actions.contains(.delete) ? [UIMenu(options: .displayInline, children: [action(.delete)])] : []
            return UIMenu(children: main + destructive)
        }

        @available(iOS 17.0, *)
        func textView(
            _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
        ) -> UITextItem.MenuConfiguration? {
            guard case .textAttachment = textItem.content, parent.imageActions != nil,
                let item = ImageItem.at(textItem.range.location, in: textView.textStorage)
            else { return UITextItem.MenuConfiguration(menu: defaultMenu) }
            guard let menu = imageMenu(for: item) else { return nil }
            return UITextItem.MenuConfiguration(preview: .default, menu: menu)
        }

        /// Carries out an action on the picture the menu or VoiceOver offered it for, if it is still there.
        func perform(_ action: ImageAction, on item: ImageItem) {
            guard let view, ImageItem.at(item.index, in: view.textStorage) == item else { return }
            switch action {
            case .copy: withOriginal(of: item, failure: "The image couldn’t be copied.") { $0.copy($1, item: item) }
            case .share: withOriginal(of: item, failure: "The image couldn’t be shared.") { $0.share($1, item: item) }
            case .save:
                withOriginal(of: item, failure: "The image couldn’t be saved to Photos.") { $0.save($1) }
            case .describe: parent.imageActions?.describe?()
            case .delete: deleteImage(item)
            }
        }

        /// Reads the stored original, then acts if the entry is still on screen; a lock meanwhile says nothing.
        private func withOriginal(
            of item: ImageItem, failure: String,
            _ act: @escaping @MainActor (NativeEditor.Coordinator, Data) -> Void
        ) {
            guard let id = item.attachmentID, let support = parent.imageActions else { return }
            Task { [weak self] in
                let data = await support.original(id)
                guard let self, self.view?.window != nil else { return }
                guard let data else {
                    support.report(failure)
                    return
                }
                act(self, data)
            }
        }

        private func copy(_ data: Data, item: ImageItem) {
            let type = item.type(of: data)
            Task { [weak self] in
                let representations = await Task.detached(priority: .userInitiated) {
                    ImageItem.pasteboardRepresentations(of: data, type: type)
                }.value
                guard let self, let view = self.view, view.window != nil else { return }
                view.pasteboard.setItems([representations])
                JournalAccessibility.announce("Copied")
            }
        }

        /// Copies a picture the person selected, as Copy in its menu does, keeping the entry's own Markdown so pasting
        /// into an entry works as before. No text types, which other apps would take instead of the picture.
        func copySelected(_ item: ImageItem, markdown: String?) -> Bool {
            guard imageActions(for: item).contains(.copy), let id = item.attachmentID,
                let support = parent.imageActions
            else { return false }
            Task { [weak self] in
                guard let data = await support.original(id) else {
                    support.report("The image couldn’t be copied.")
                    return
                }
                let type = item.type(of: data)
                var representations: [String: Any] = await Task.detached(priority: .userInitiated) {
                    ImageItem.pasteboardRepresentations(of: data, type: type)
                }.value
                if let markdown { representations[PastedImages.markdownType] = Data(markdown.utf8) }
                guard let self, let view = self.view, view.window != nil else { return }
                view.pasteboard.setItems([representations])
            }
            return true
        }

        private func share(_ data: Data, item: ImageItem) {
            guard let view, let presenter = Self.presenter(for: view) else { return }
            let controller = UIActivityViewController(
                activityItems: [ImageShareItem(data: data, type: item.type(of: data))], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = imageRect(item) ?? CGRect(origin: view.contentOffset, size: .zero)
            }
            presenter.present(controller, animated: true)
            sharing = controller
        }

        private func save(_ data: Data) {
            Task { [weak self] in
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard let self, let view = self.view, view.window != nil else { return }
                guard status == .authorized || status == .limited else {
                    self.photosAccessIsOff()
                    return
                }
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                    }
                    JournalAccessibility.announce("Saved to Photos")
                } catch {
                    guard self.view?.window != nil else { return }
                    self.parent.imageActions?.report("The image couldn’t be saved to Photos.")
                }
            }
        }

        private func photosAccessIsOff() {
            guard let view, let presenter = Self.presenter(for: view) else { return }
            let alert = UIAlertController(
                title: "Photos Access Is Off", message: "Allow photo library access in Settings to save images.",
                preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "Open Settings", style: .default) { _ in
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            presenter.present(alert, animated: true)
            sharing = alert
        }

        /// Removes the picture: on its own line with that line, inside a line alone. One undo step.
        func deleteImage(_ item: ImageItem) {
            guard parent.editable, let view, ImageItem.at(item.index, in: view.textStorage) == item else { return }
            let range = item.deletionRange(in: view.textStorage.string as NSString)
            // Writing starts, as a tap on the picture would, so Undo (shake, the three-finger gesture, ⌘Z) reaches
            // the step: the text view keeps its own undo history, which only it uses while it has focus.
            view.becomeFirstResponder()
            replace(NSAttributedString(), range: range, actionName: "Delete Image")
            // Focus moves to the text first, so the announcement isn't cut off by the change.
            UIAccessibility.post(notification: .layoutChanged, argument: view)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { JournalAccessibility.announce("Image deleted") }
        }

        /// A share sheet or alert this editor showed goes when the entry leaves the screen, as when the app locks.
        func dismissImagePresentations() {
            dismissImageMenu()
            if let sharing, sharing.presentingViewController != nil { sharing.dismiss(animated: false) }
            sharing = nil
        }

        /// A picture's menu and its preview don't stay open while the app is away, where they'd show the picture.
        func dismissImageMenu() {
            guard let view else { return }
            for case let interaction as UIContextMenuInteraction in view.interactions { interaction.dismissMenu() }
        }

        /// The picture's rectangle in the text view's content.
        func imageRect(_ item: ImageItem) -> CGRect? {
            guard let view, item.index < view.textStorage.length else { return nil }
            let layout = view.layoutManager
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: item.index, length: 1), actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            return layout.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
                .offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
        }

        private static func presenter(for view: UIView) -> UIViewController? {
            var controller = view.window?.rootViewController
            while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
                controller = presented
            }
            return controller
        }

        /// What the picture elements were last made from; layout alone, such as scrolling, changes none of it.
        struct PictureElementsSource: Equatable {
            var document: JournalDocument
            var shown: Set<UUID>
            var loading: Set<UUID>
            var editable: Bool
            var describes: Bool
        }

        /// An element for every picture in the entry, after the entry's text, so VoiceOver can reach and act on each.
        func synchronizePictureElements() {
            guard let view, let container = view.superview as? JournalWritingView else { return }
            let source = PictureElementsSource(
                document: parent.document, shown: Set(parent.images.keys), loading: parent.loadingImages,
                editable: parent.editable, describes: parent.imageActions?.describe != nil)
            guard source != pictureElementsSource else { return }
            pictureElementsSource = source
            var items: [ImageItem] = []
            let storage = view.textStorage
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) {
                value, range, _ in
                guard value != nil else { return }
                for index in range.location..<NSMaxRange(range) {
                    if let item = ImageItem.at(index, in: storage) { items.append(item) }
                }
            }
            let elements = items.map { item -> PictureAccessibilityElement in
                let existing = container.pictureElements.lazy.compactMap { $0 as? PictureAccessibilityElement }
                    .first { $0.item == item }
                let element = existing ?? PictureAccessibilityElement(accessibilityContainer: container)
                element.configure(item, coordinator: self)
                return element
            }
            container.pictureElements = elements
        }
    }

    /// A picture as VoiceOver reaches it: its description, the image trait, and the menu's actions. Its frame is
    /// worked out when asked, so VoiceOver can move to a picture further down the entry.
    final class PictureAccessibilityElement: UIAccessibilityElement {
        private(set) var item: ImageItem?
        private weak var coordinator: NativeEditor.Coordinator?

        func configure(_ item: ImageItem, coordinator: NativeEditor.Coordinator) {
            self.item = item
            self.coordinator = coordinator
            accessibilityTraits = .image
            let id = item.attachmentID
            let shown = id.map { coordinator.parent.images[$0] != nil } ?? false
            if shown {
                accessibilityLabel = item.description.isEmpty ? "Image" : item.description
            } else {
                let loading = id.map { coordinator.parent.loadingImages.contains($0) } ?? false
                let status =
                    id == nil ? "Remote image. Not downloaded." : loading ? "Loading Image." : "Image unavailable."
                accessibilityLabel = status + (item.description.isEmpty ? "" : " " + item.description)
            }
            accessibilityCustomActions = coordinator.imageActions(for: item).map { kind in
                UIAccessibilityCustomAction(name: kind.spoken) { [weak coordinator] _ in
                    guard let coordinator else { return false }
                    coordinator.perform(kind, on: item)
                    return true
                }
            }
        }

        override var accessibilityFrame: CGRect {
            get {
                guard let item, let coordinator, let view = coordinator.view, let rect = coordinator.imageRect(item)
                else { return .zero }
                return UIAccessibility.convertToScreenCoordinates(rect, in: view)
            }
            set {}
        }

        override func accessibilityElementDidBecomeFocused() {
            guard let item, let coordinator, let view = coordinator.view, let rect = coordinator.imageRect(item) else {
                return
            }
            view.scrollRectToVisible(rect, animated: false)
        }

        /// A double tap neither selects the picture nor brings up the keyboard; the actions act on it.
        override func accessibilityActivate() -> Bool { true }
    }

    /// The original image for the share sheet, in memory with its own type, offered as “Image”.
    final class ImageShareItem: NSObject, UIActivityItemSource {
        let data: Data
        let type: UTType
        init(data: Data, type: UTType) {
            self.data = data
            self.type = type
        }
        func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { data }
        func activityViewController(
            _ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?
        ) -> Any? { data }
        func activityViewController(
            _ controller: UIActivityViewController,
            dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
        ) -> String { type.identifier }
        func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = ImageItem.fileName(for: type)
            if let image = UIImage(data: data) { metadata.imageProvider = NSItemProvider(object: image) }
            return metadata
        }
    }
#endif
