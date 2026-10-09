import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Typing in one table cell, which extends a single undo step until the person moves on.
struct CellTyping: Hashable {
    let table: UUID
    let cell: TableCellAddress
}

/// Native cell views share the surrounding entry's mutation and undo boundary.
@MainActor final class InlineTables {
    private weak var host: JournalTextView?
    private let actions: EditorActions
    private let replace: (NSAttributedString, NSRange, CellTyping?) -> Void
    private var grids: [UUID: InlineTableGrid] = [:]
    private var updating = false
    private var size: CGFloat = 17
    private var images: [UUID: Data] = [:]
    private var editable = false
    var active: InlineTableGrid? { grids.values.first { $0.activeCell != nil } }
    init(
        host: JournalTextView, actions: EditorActions,
        replace: @escaping (NSAttributedString, NSRange, CellTyping?) -> Void
    ) {
        self.host = host
        self.actions = actions
        self.replace = replace
    }
    func reset() {
        for grid in grids.values { grid.removeFromSuperview() }
        grids = [:]
        updateAccessibility()
    }
    private func updateAccessibility() {
        #if os(iOS)
            (host?.superview as? JournalWritingView)?.updateAccessibility()
        #endif
    }
    private var storage: NSTextStorage? {
        #if os(macOS)
            host?.textStorage
        #else
            host?.textStorage
        #endif
    }
    func synchronize(size: CGFloat, editable: Bool, images: [UUID: Data]? = nil) {
        guard !updating, let host, let storage else { return }
        updating = true
        defer { updating = false }
        if let images { self.images = images }
        self.size = size
        self.editable = editable
        var retained = Set<UUID>()
        storage.enumerateAttribute(.journalTable, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let data = value as? Data,
                let block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: data),
                let table = block.table, storage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil
            else { return }
            let width = max(40, host.bounds.width - 20)
            updateAttachment(block, table: table, at: range, width: width)
            guard let frame = attachmentFrame(range) else { return }
            #if os(macOS)
                let visible = host.visibleRect.intersection(frame)
            #else
                let visible = host.bounds.intersection(frame)
            #endif
            guard !visible.isNull || grids[block.id]?.activeCell != nil else { return }
            retained.insert(block.id)
            let grid = grids[block.id] ?? makeGrid(block, range: range)
            #if os(macOS)
                grid.frame = frame
            #else
                grid.frame = grid.superview === host ? frame : host.convert(frame, to: grid.superview)
            #endif
            grid.viewport = visible.isNull ? .zero : visible.offsetBy(dx: -frame.minX, dy: -frame.minY)
            grid.images = self.images
            grid.configure(block, size: size, editable: editable)
        }
        defer { updateAccessibility() }
        for (id, grid) in grids where !retained.contains(id) {
            grid.removeFromSuperview()
            grids.removeValue(forKey: id)
        }
    }
    private func updateAttachment(_ block: DocumentBlock, table: DocumentTable, at range: NSRange, width: CGFloat) {
        guard let storage, let host,
            let existing = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        else { return }
        let layout = TablePresentation.layout(table, width: width, size: size)
        #if os(macOS)
            let current = existing.attachmentCell?.cellSize() ?? .zero
        #else
            let current = existing.bounds.size
        #endif
        guard abs(current.width - width) > 0.5 || abs(current.height - layout.height) > 0.5,
            let attachment = TablePresentation.render(block, width: width, size: size).attribute(
                .attachment, at: 0, effectiveRange: nil)
        else { return }
        host.undoManager?.disableUndoRegistration()
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: range.location, length: 1))
        host.undoManager?.enableUndoRegistration()
    }
    private func attachmentFrame(_ range: NSRange) -> CGRect? {
        guard let host else { return nil }
        #if os(macOS)
            guard let layout = host.layoutManager, let container = host.textContainer else { return nil }
            let inset = host.textContainerOrigin
        #else
            let layout = host.layoutManager
            let container = host.textContainer
            let inset = CGPoint(x: host.textContainerInset.left, y: host.textContainerInset.top)
        #endif
        // Only the text up to the table is laid out, not the rest of a long entry.
        layout.ensureLayout(forCharacterRange: NSRange(location: range.location, length: 1))
        let glyphs = layout.glyphRange(
            forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
        return layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: inset.x, dy: inset.y)
    }
    private func makeGrid(_ block: DocumentBlock, range: NSRange) -> InlineTableGrid {
        let grid = InlineTableGrid(block: block, size: size)
        grid.actions = actions
        grid.sharedUndo = { [weak host] in host?.undoManager }
        grid.changed = { [weak self] updated, cell in self?.commit(updated, typingIn: cell) }
        grid.exit = { [weak self] forward in self?.leave(block.id, fallback: range.location, forward: forward) }
        grid.editing = { [weak self, weak grid] editing in
            guard let self else { return }
            // A grid being torn down is already gone; forgetting departed views ends its focus.
            if let grid {
                self.actions.setEditing(editing, by: grid)
            } else {
                self.actions.forgetDeparted()
            }
            self.actions.editingTable = editing
            if editing { grid?.publishAlignment() } else { self.actions.tableAlignment = nil }
            if editing, let range = self.range(block.id) { self.select(range) }
        }
        #if os(macOS)
            host?.addSubview(grid)
        #else
            if let container = host?.superview as? JournalWritingView {
                container.addSubview(grid)
                container.updateAccessibility()
            } else {
                host?.addSubview(grid)
            }
            grid.reveal = { [weak host, weak grid] rectangle in
                guard let host, let grid else { return }
                host.scrollRectToVisible(grid.convert(rectangle, to: host).insetBy(dx: 0, dy: -8), animated: false)
            }
        #endif
        grids[block.id] = grid
        return grid
    }
    private func range(_ id: UUID) -> NSRange? {
        guard let storage else { return nil }
        var result: NSRange?
        storage.enumerateAttribute(.journalTable, in: NSRange(location: 0, length: storage.length)) {
            value, range, stop in
            guard let data = value as? Data,
                let block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: data), block.id == id
            else { return }
            result = NSRange(location: range.location, length: 1)
            stop.pointee = true
        }
        return result
    }
    private func commit(_ block: DocumentBlock, typingIn cell: TableCellAddress?) {
        guard editable, let host, let range = range(block.id) else { return }
        let text =
            block.table == nil
            ? NSAttributedString() : TablePresentation.render(block, width: max(40, host.bounds.width - 20), size: size)
        replace(text, range, cell.map { CellTyping(table: block.id, cell: $0) })
        synchronize(size: size, editable: editable)
    }
    func focus(at selection: NSRange) {
        guard let storage, selection.location < storage.length,
            let data = storage.attribute(.journalTable, at: selection.location, effectiveRange: nil) as? Data,
            let block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: data)
        else { return }
        synchronize(size: size, editable: editable)
        #if os(iOS)
            if let host, let frame = attachmentFrame(selection) {
                host.scrollRectToVisible(
                    CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(frame.height, 60)),
                    animated: false)
            }
        #endif
        grids[block.id]?.focus()
    }
    private func select(_ range: NSRange) {
        #if os(macOS)
            host?.setSelectedRange(range)
        #else
            host?.selectedRange = range
        #endif
    }
    private func leave(_ id: UUID, fallback: Int, forward: Bool) {
        guard let host, let storage else { return }
        let range = range(id)
        let location =
            forward
            ? range.map { min(storage.length, NSMaxRange($0) + 1) } ?? min(storage.length, fallback)
            : range?.location ?? min(storage.length, fallback)
        select(NSRange(location: location, length: 0))
        host.typingAttributes = RichText.attributes(kind: "paragraph", size: size)
        #if os(macOS)
            host.window?.makeFirstResponder(host)
        #else
            host.becomeFirstResponder()
        #endif
    }
}
