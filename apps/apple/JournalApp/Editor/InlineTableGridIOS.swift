#if os(iOS)
    import JournalCore
    import UIKit

    @MainActor final class InlineTableGrid: UIScrollView, UITextViewDelegate {
        var block: DocumentBlock
        var textSize: CGFloat
        /// Reports an edited table, with the cell when the edit was typing in it.
        var changed: ((DocumentBlock, TableCellAddress?) -> Void)?
        var reveal: ((CGRect) -> Void)?
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
        var activeCell: TableCellTextView? { cells.values.first { $0.isFirstResponder } }

        init(block: DocumentBlock, size: CGFloat) {
            self.block = block
            textSize = size
            super.init(frame: .zero)
            isDirectionalLockEnabled = true
            showsVerticalScrollIndicator = false
            addSubview(canvas)
            accessibilityLabel = "Table"
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { nil }
        func configure(_ block: DocumentBlock, size: CGFloat, editable: Bool) {
            self.block = block
            textSize = size
            self.editable = editable
            refreshCells()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            refreshCells()
        }
        private func refreshCells() {
            guard !updating, let table = block.table, bounds.width > 0 else { return }
            updating = true
            defer { updating = false }
            let layout = TablePresentation.layout(table, width: bounds.width, size: textSize)
            contentSize = CGSize(width: layout.width, height: layout.height)
            canvas.frame = CGRect(origin: .zero, size: contentSize)
            canvas.layout = layout
            let visible = CGRect(x: contentOffset.x, y: viewport.minY, width: bounds.width, height: viewport.height)
            var retained = Set<TableCellAddress>()
            for row in table.rows.indices {
                for column in table.rows[row].indices {
                    let address = TableCellAddress(row: row, column: column)
                    let frame = layout.cell(row: row, column: column)
                    guard frame.intersects(visible) || cells[address]?.isFirstResponder == true else { continue }
                    retained.insert(address)
                    let cell = cells[address] ?? makeCell(address)
                    cell.frame = frame.insetBy(dx: 0.5, dy: 0.5)
                    cell.isEditable = editable
                    cell.backgroundColor = .clear
                    cell.accessibilityLabel = "\(row == 0 ? "Header" : "Row \(row + 1)"), column \(column + 1)"
                    let value = TablePresentation.text(
                        table.rows[row][column], size: textSize, images: images, header: row == 0)
                    if cell.markedTextRange == nil, cell.attributedText != value {
                        let selection = cell.selectedRange
                        cell.attributedText = value
                        cell.selectedRange = NSRange(location: min(selection.location, value.length), length: 0)
                    }
                    if value.length == 0 {
                        cell.typingAttributes = RichText.attributes(
                            kind: row == 0 ? "tableHeader" : "paragraph", size: textSize)
                    }
                    if let alignment = table.alignments.indices.contains(column) ? table.alignments[column] : nil {
                        cell.textAlignment = alignment == "right" ? .right : alignment == "center" ? .center : .left
                    }
                }
            }
            for (address, cell) in cells where !retained.contains(address) {
                cell.removeFromSuperview()
                cells.removeValue(forKey: address)
            }
            accessibilityElements = cells.sorted {
                $0.key.row == $1.key.row ? $0.key.column < $1.key.column : $0.key.row < $1.key.row
            }.map(\.value)
        }
        private func makeCell(_ address: TableCellAddress) -> TableCellTextView {
            let cell = TableCellTextView()
            cell.address = address
            cell.delegate = self
            cell.isAccessibilityElement = true
            let padding = TablePresentation.padding
            cell.textContainerInset = UIEdgeInsets(
                top: padding.height - 0.5, left: padding.width - 0.5, bottom: padding.height - 0.5,
                right: padding.width - 0.5)
            cell.textContainer.lineFragmentPadding = 0
            cell.isScrollEnabled = false
            cell.adjustsFontForContentSizeCategory = true
            cell.traverse = { [weak self, weak cell] direction in
                guard let cell else { return }
                self?.move(from: cell.address, direction: direction)
            }
            cell.commit = { [weak self, weak cell] in if let cell { self?.textViewDidChange(cell) } }
            cell.history = { [weak self] redo in
                let undo = self?.sharedUndo?()
                if redo { undo?.redo() } else { undo?.undo() }
            }
            if let actions { cell.inputAccessoryView = WritingAccessory(actions: actions) }
            WritingAccessory.hideSystemFormatting(of: cell)
            cell.formattingActions = actions
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
            scrollRectToVisible(frame, animated: false)
            refreshCells()
            cells[address]?.becomeFirstResponder()
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
        func textViewDidBeginEditing(_ textView: UITextView) {
            editing?(true)
            reveal?(textView.convert(textView.bounds, to: self))
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            textViewDidChange(textView)
            editing?(false)
        }
        func textViewDidChange(_ textView: UITextView) {
            guard let cell = textView as? TableCellTextView else { return }
            commit(cell)
            actions?.formattingSelectionChanged()
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            actions?.formattingSelectionChanged()
        }
        func commit(_ cell: TableCellTextView, typing: Bool = true) {
            guard !updating, cell.markedTextRange == nil, var table = block.table else { return }
            table.replaceCell(
                row: cell.address.row, column: cell.address.column,
                runs: TablePresentation.runs(cell.textStorage, header: cell.address.row == 0))
            guard table != block.table else { return }
            block.table = table
            changed?(block, typing ? cell.address : nil)
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let cell = textView as? TableCellTextView, textView.markedTextRange == nil else { return true }
            if text == "\n" {
                move(from: cell.address, direction: block.table?.columnCount ?? 1)
                return false
            }
            if text == "\t" {
                move(from: cell.address, direction: 1)
                return false
            }
            if text.contains("\n") || text.contains("\r") {
                let normalized = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(
                    of: "\n", with: " "
                ).replacingOccurrences(of: "\r", with: " ")
                textView.textStorage.replaceCharacters(
                    in: range, with: NSAttributedString(string: normalized, attributes: textView.typingAttributes))
                textView.selectedRange = NSRange(location: range.location + normalized.utf16.count, length: 0)
                textViewDidChange(textView)
                return false
            }
            return true
        }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement])
            -> UIMenu?
        {
            guard let cell = textView as? TableCellTextView else { return nil }
            return UIMenu(
                children: suggestedActions + [UIMenu(title: "Table", children: structuralActions(cell.address))])
        }
        private func structuralActions(_ address: TableCellAddress) -> [UIMenuElement] {
            [
                UIAction(title: "Add Row Below") { [weak self] _ in self?.changeStructure(.addRow, at: address) },
                UIAction(title: "Add Column After") { [weak self] _ in self?.changeStructure(.addColumn, at: address) },
                UIMenu(
                    title: "Alignment",
                    children: ["left", "center", "right"].map { alignment in
                        UIAction(title: alignment.capitalized) { [weak self] _ in
                            self?.changeStructure(.align(alignment), at: address)
                        }
                    }),
                UIAction(title: "Delete Row", attributes: .destructive) { [weak self] _ in
                    self?.changeStructure(.deleteRow, at: address)
                },
                UIAction(title: "Delete Column", attributes: .destructive) { [weak self] _ in
                    self?.changeStructure(.deleteColumn, at: address)
                },
                UIAction(title: "Delete Table", attributes: .destructive) { [weak self] _ in
                    self?.changeStructure(.deleteTable, at: address)
                },
            ]
        }
        private func changeStructure(_ action: TableStructureAction, at address: TableCellAddress) {
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
            } else {
                exit?(true)
            }
        }
    }

    final class TableCellTextView: UITextView, FormattingPanelClosing {
        var address = TableCellAddress(row: 0, column: 0)
        /// Shows the Format panel in place of the keyboard while it's open, as in the entry's text.
        weak var formattingActions: EditorActions?
        override var inputView: UIView? {
            get { formattingActions?.formattingInputView ?? super.inputView }
            set { super.inputView = newValue }
        }
        func closeFormattingPanel() {
            if markedTextRange == nil { formattingActions?.closeFormatting?(true) }
        }
        var traverse: ((Int) -> Void)?
        var history: ((Bool) -> Void)?
        var commit: (() -> Void)?
        override var undoManager: UndoManager? { nil }
        override func unmarkText() {
            super.unmarkText()
            commit?()
        }
        override var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(nextCell)),
                UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(previousCell)),
                UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(undoEntry)),
                UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(redoEntry)),
            ] + [formattingActions?.formattingEscapeCommand()].compactMap { $0 } + (super.keyCommands ?? [])
        }
        @objc private func nextCell() { if markedTextRange == nil { traverse?(1) } }
        @objc private func previousCell() { if markedTextRange == nil { traverse?(-1) } }
        @objc private func undoEntry() { if markedTextRange == nil { history?(false) } }
        @objc private func redoEntry() { if markedTextRange == nil { history?(true) } }
    }

    /// One continuous hairline grid, including the outer edge, drawn behind the cells.
    private final class TableCanvas: UIView {
        var layout: TablePresentation.Layout? {
            didSet { setNeedsDisplay() }
        }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            contentMode = .redraw
        }
        required init?(coder: NSCoder) { nil }
        override func draw(_ rect: CGRect) {
            guard let layout else { return }
            let line = 1 / max(1, traitCollection.displayScale)
            UIColor.separator.setFill()
            var x: CGFloat = 0
            for _ in 0...layout.columns {
                UIRectFill(CGRect(x: min(x, bounds.width - line), y: 0, width: line, height: layout.height))
                x += layout.columnWidth
            }
            var y: CGFloat = 0
            for height in layout.rowHeights + [0] {
                UIRectFill(CGRect(x: 0, y: min(y, bounds.height - line), width: layout.width, height: line))
                y += height
            }
        }
    }
#endif
