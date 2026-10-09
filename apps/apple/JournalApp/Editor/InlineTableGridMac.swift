#if os(macOS)
    import AppKit
    import JournalCore

    @MainActor final class InlineTableGrid: NSScrollView, NSTextViewDelegate {
        var block: DocumentBlock
        var textSize: CGFloat
        /// Reports an edited table, with the cell when the edit was typing in it.
        var changed: ((DocumentBlock, TableCellAddress?) -> Void)?
        var exit: ((Bool) -> Void)?
        var editing: ((Bool) -> Void)?
        /// Resolved when used: the entry's undo manager may not exist yet when the grid is created.
        var sharedUndo: (() -> UndoManager?)?
        var actions: EditorActions?
        var editable = true
        var viewport = CGRect.zero
        private var cells: [TableCellAddress: TableCellTextView] = [:]
        private var updating = false
        private let canvas = TableCanvas()
        var images: [UUID: Data] = [:]
        var activeCell: TableCellTextView? { cells.values.first { $0.window?.firstResponder === $0 } }
        init(block: DocumentBlock, size: CGFloat) {
            self.block = block
            textSize = size
            super.init(frame: .zero)
            drawsBackground = false
            hasHorizontalScroller = true
            autohidesScrollers = true
            documentView = canvas
            setAccessibilityLabel("Table")
        }
        required init?(coder: NSCoder) { nil }
        func configure(_ block: DocumentBlock, size: CGFloat, editable: Bool) {
            self.block = block
            textSize = size
            self.editable = editable
            refreshCells()
        }
        override func layout() {
            super.layout()
            refreshCells()
        }
        private func refreshCells() {
            guard !updating, let table = block.table, bounds.width > 0 else { return }
            updating = true
            defer { updating = false }
            let layout = TablePresentation.layout(table, width: bounds.width, size: textSize)
            canvas.frame = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
            canvas.layout = layout
            let visible = CGRect(
                x: contentView.bounds.minX, y: viewport.minY, width: bounds.width, height: viewport.height)
            var retained = Set<TableCellAddress>()
            for row in table.rows.indices {
                for column in table.rows[row].indices {
                    let address = TableCellAddress(row: row, column: column)
                    let frame = layout.cell(row: row, column: column)
                    guard frame.intersects(visible) || cells[address].map({ $0.window?.firstResponder === $0 }) == true
                    else { continue }
                    retained.insert(address)
                    let cell = cells[address] ?? makeCell(address)
                    cell.frame = frame.insetBy(dx: 0.5, dy: 0.5)
                    cell.isEditable = editable
                    cell.setAccessibilityLabel("\(row == 0 ? "Header" : "Row \(row + 1)"), column \(column + 1)")
                    let value = TablePresentation.text(
                        table.rows[row][column], size: textSize, images: images, header: row == 0)
                    if !cell.hasMarkedText(), cell.attributedString() != value {
                        let selection = cell.selectedRange()
                        cell.textStorage?.setAttributedString(value)
                        cell.setSelectedRange(NSRange(location: min(selection.location, value.length), length: 0))
                    }
                    if value.length == 0 {
                        cell.typingAttributes = RichText.attributes(
                            kind: row == 0 ? "tableHeader" : "paragraph", size: textSize)
                    }
                    if let alignment = table.alignments.indices.contains(column) ? table.alignments[column] : nil {
                        cell.alignment = alignment == "right" ? .right : alignment == "center" ? .center : .left
                    }
                }
            }
            for (address, cell) in cells where !retained.contains(address) {
                cell.removeFromSuperview()
                cells.removeValue(forKey: address)
            }
            canvas.setAccessibilityChildren(
                cells.sorted {
                    $0.key.row == $1.key.row ? $0.key.column < $1.key.column : $0.key.row < $1.key.row
                }.map(\.value))
        }
        private func makeCell(_ address: TableCellAddress) -> TableCellTextView {
            let cell = TableCellTextView(frame: .zero)
            cell.address = address
            cell.delegate = self
            cell.allowsUndo = false
            cell.isRichText = true
            cell.importsGraphics = false
            cell.textContainerInset = NSSize(
                width: TablePresentation.padding.width - 0.5, height: TablePresentation.padding.height - 0.5)
            cell.drawsBackground = false
            cell.textContainer?.lineFragmentPadding = 0
            cell.textContainer?.widthTracksTextView = true
            cell.commit = { [weak self, weak cell] in if let cell { self?.commit(cell) } }
            cell.history = { [weak self] redo in
                let undo = self?.sharedUndo?()
                if redo { undo?.redo() } else { undo?.undo() }
            }
            cell.tableMenu = { [weak self] in self?.menu(address) }
            cell.cancelFormatting = { [weak self] in
                guard let close = self?.actions?.closeFormatting else { return false }
                close(true)
                return true
            }
            canvas.addSubview(cell)
            cells[address] = cell
            return cell
        }
        func focus(_ address: TableCellAddress = TableCellAddress(row: 0, column: 0)) {
            guard let table = block.table, table.rows.indices.contains(address.row),
                table.rows[address.row].indices.contains(address.column)
            else { return }
            let layout = TablePresentation.layout(table, width: bounds.width, size: textSize)
            let frame = layout.cell(row: address.row, column: address.column)
            viewport = viewport.union(frame)
            canvas.scrollToVisible(frame)
            refreshCells()
            if let cell = cells[address] { window?.makeFirstResponder(cell) }
        }
        private func move(from address: TableCellAddress, direction: Int) {
            guard let table = block.table else { return }
            activeCell?.unmarkText()
            let columns = table.columnCount
            let index = address.row * columns + address.column + direction
            if index < 0 || index >= table.rows.count * columns {
                exit?(index >= 0)
                return
            }
            focus(TableCellAddress(row: index / columns, column: index % columns))
        }
        func textDidBeginEditing(_ notification: Notification) { editing?(true) }
        func textDidEndEditing(_ notification: Notification) {
            textDidChange(notification)
            editing?(false)
        }
        func textDidChange(_ notification: Notification) {
            guard let cell = notification.object as? TableCellTextView else { return }
            commit(cell)
            actions?.formattingSelectionChanged()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            actions?.formattingSelectionChanged()
            publishAlignment()
        }
        func commit(_ cell: TableCellTextView, typing: Bool = true) {
            guard !updating, !cell.hasMarkedText(), var table = block.table else { return }
            table.replaceCell(
                row: cell.address.row, column: cell.address.column,
                runs: TablePresentation.runs(cell.attributedString(), header: cell.address.row == 0))
            guard table != block.table else { return }
            block.table = table
            changed?(block, typing ? cell.address : nil)
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let cell = textView as? TableCellTextView, !cell.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                move(from: cell.address, direction: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                move(from: cell.address, direction: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                move(from: cell.address, direction: block.table?.columnCount ?? 1)
                return true
            }
            return false
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?)
            -> Bool
        {
            guard !updating, let text = replacementString, text.contains("\n") || text.contains("\r"),
                let cell = textView as? TableCellTextView, !cell.hasMarkedText()
            else { return true }
            let normalized = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            cell.textStorage?.replaceCharacters(
                in: affectedCharRange, with: NSAttributedString(string: normalized, attributes: cell.typingAttributes))
            cell.setSelectedRange(NSRange(location: affectedCharRange.location + normalized.utf16.count, length: 0))
            commit(cell)
            return false
        }
        private struct MenuAction {
            let action: TableStructureAction
            let address: TableCellAddress
        }
        /// The Table submenu of a cell's context menu, from the one list every table menu shows (TableMenu). A
        /// read-only entry has none.
        private func menu(_ address: TableCellAddress) -> NSMenu? {
            guard editable else { return nil }
            let menu = NSMenu(title: "Table")
            let alignment = TablePresentation.alignment(of: block.table, column: address.column)
            for (index, group) in TableMenu.groups(alignment: alignment).enumerated() {
                if index > 0 { menu.addItem(.separator()) }
                for entry in group {
                    switch entry {
                    case .item(let item):
                        menu.addItem(menuItem(item, address))
                    case .submenu(let title, let items):
                        let parent = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
                        let submenu = NSMenu(title: title)
                        for item in items { submenu.addItem(menuItem(item, address)) }
                        parent.submenu = submenu
                    }
                }
            }
            return menu
        }
        private func menuItem(_ choice: TableMenu.Item, _ address: TableCellAddress) -> NSMenuItem {
            let item = NSMenuItem(title: choice.title, action: #selector(changeStructure(_:)), keyEquivalent: "")
            item.target = self
            item.state = choice.isChecked ? .on : .off
            item.representedObject = MenuAction(action: choice.action, address: address)
            return item
        }
        @objc private func changeStructure(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? MenuAction else { return }
            apply(action.action, at: action.address)
        }
        /// Applies a table action from the menu bar to the cell being edited.
        func applyToActiveCell(_ action: TableStructureAction) {
            guard editable, let address = activeCell?.address else { return }
            apply(action, at: address)
        }
        /// Tells Format ▸ Table which alignment is checked: the focused cell's column.
        func publishAlignment() {
            let alignment = activeCell.map { TablePresentation.alignment(of: block.table, column: $0.address.column) }
            DispatchQueue.main.async { [weak actions] in
                if actions?.tableAlignment != alignment { actions?.tableAlignment = alignment }
            }
        }
        private func apply(_ action: TableStructureAction, at address: TableCellAddress) {
            activeCell?.unmarkText()
            guard var table = block.table else { return }
            let result = table.apply(action, row: address.row, column: address.column)
            block.table = result ? table : nil
            changed?(block, nil)
            if result {
                focus(
                    TableCellAddress(
                        row: min(address.row, table.rows.count - 1), column: min(address.column, table.columnCount - 1))
                )
                publishAlignment()
            } else {
                exit?(true)
            }
        }
    }
    /// One continuous hairline grid, including the outer edge, drawn behind the cells.
    private final class TableCanvas: NSView {
        var layout: TablePresentation.Layout? {
            didSet { needsDisplay = true }
        }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let layout else { return }
            let scale = window?.backingScaleFactor ?? 2
            let line = 1 / scale
            NSColor.separatorColor.setFill()
            var x: CGFloat = 0
            for _ in 0...layout.columns {
                NSRect(x: min(x, bounds.width - line), y: 0, width: line, height: layout.height).fill()
                x += layout.columnWidth
            }
            var y: CGFloat = 0
            for height in layout.rowHeights + [0] {
                NSRect(x: 0, y: min(y, bounds.height - line), width: layout.width, height: line).fill()
                y += height
            }
        }
    }
    final class TableCellTextView: NSTextView {
        var address = TableCellAddress(row: 0, column: 0)
        var commit: (() -> Void)?
        var history: ((Bool) -> Void)?
        var tableMenu: (() -> NSMenu?)?
        /// Closes the Formatting popover when it's shown; false when there's none.
        var cancelFormatting: (() -> Bool)?
        /// Escape closes the Formatting popover while the cell keeps focus, unless an input method is composing.
        override func cancelOperation(_ sender: Any?) {
            if !hasMarkedText(), cancelFormatting?() == true { return }
            super.cancelOperation(sender)
        }
        override func unmarkText() {
            super.unmarkText()
            commit?()
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            let result = super.menu(for: event) ?? NSMenu()
            if let table = tableMenu?() {
                result.addItem(.separator())
                let item = result.addItem(withTitle: "Table", action: nil, keyEquivalent: "")
                item.submenu = table
            }
            return result
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Key equivalents reach every view in the window; only the focused cell may claim ⌘Z.
            if window?.firstResponder === self, event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "z", !hasMarkedText()
            {
                history?(event.modifierFlags.contains(.shift))
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
#endif
