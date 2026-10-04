import SwiftUI

#if os(macOS)
    import AppKit

    extension NativeEditor.Coordinator {
        /// Shows the entry's pictures at the editor's current width, with the images loaded so far and in the current
        /// appearance, keeping the text in view where it was.
        func refreshImages(force: Bool = false) {
            guard let view, view.bounds.width.isFinite, view.bounds.width > 20 else { return }
            let width = max(40, view.bounds.width - 20)
            guard
                force || abs(imageWidth - width) > 0.5 || imageIDs != Set(parent.images.keys)
                    || loadingIDs != parent.loadingImages
                    || appearance != parent.colorScheme
            else { return }
            guard !applying, !view.hasMarkedText(), let storage = view.textStorage,
                let layout = view.layoutManager, let container = view.textContainer
            else { return }
            applying = true
            defer { applying = false }
            let selection = view.selectedRange()
            let typing = view.typingAttributes
            let origin = view.visibleRect.origin
            let anchor = ImagePresentation.visibleAnchor(
                storage, layout: layout, container: container, viewport: view.visibleRect)
            let before = ImagePresentation.anchorY(anchor, layout: layout, container: container)
            view.undoManager?.disableUndoRegistration()
            ImagePresentation.update(storage, images: parent.images, size: parent.fontSize, layout: imageLayout)
            view.undoManager?.enableUndoRegistration()
            view.setSelectedRange(selection)
            view.typingAttributes = typing
            if let before, let after = ImagePresentation.anchorY(anchor, layout: layout, container: container) {
                view.scroll(NSPoint(x: origin.x, y: max(0, origin.y + after - before)))
            }
            appearance = parent.colorScheme
            imageIDs = Set(parent.images.keys)
            loadingIDs = parent.loadingImages
            imageWidth = max(40, view.bounds.width - 20)
        }
    }
#else
    import UIKit

    extension NativeEditor.Coordinator {
        /// Shows the entry's pictures at the editor's current width, with the images loaded so far and in the current
        /// appearance, keeping the text in view where it was.
        func refreshImages(force: Bool = false) {
            guard let view, view.bounds.width.isFinite, view.bounds.width > 20 else { return }
            let width = max(40, view.bounds.width - 20)
            guard
                force || abs(imageWidth - width) > 0.5 || imageIDs != Set(parent.images.keys)
                    || loadingIDs != parent.loadingImages
                    || appearance != parent.colorScheme
            else { return }
            guard !applyingImages, view.markedTextRange == nil else { return }
            applyingImages = true
            defer { applyingImages = false }
            let selection = view.selectedRange
            let typing = view.typingAttributes
            let origin = view.contentOffset
            let layout = view.layoutManager
            let container = view.textContainer
            let viewport = CGRect(
                x: origin.x, y: origin.y - view.textContainerInset.top, width: view.bounds.width,
                height: view.bounds.height)
            let anchor = ImagePresentation.visibleAnchor(
                view.textStorage, layout: layout, container: container, viewport: viewport)
            let before = ImagePresentation.anchorY(anchor, layout: layout, container: container)
            view.undoManager?.disableUndoRegistration()
            ImagePresentation.update(
                view.textStorage, images: parent.images, size: parent.fontSize, layout: imageLayout)
            view.undoManager?.enableUndoRegistration()
            view.selectedRange = selection
            view.typingAttributes = typing
            if let before, let after = ImagePresentation.anchorY(anchor, layout: layout, container: container) {
                view.setContentOffset(
                    CGPoint(x: origin.x, y: max(-view.adjustedContentInset.top, origin.y + after - before)),
                    animated: false)
            }
            appearance = parent.colorScheme
            imageIDs = Set(parent.images.keys)
            loadingIDs = parent.loadingImages
            imageWidth = max(40, view.bounds.width - 20)
        }
    }
#endif
