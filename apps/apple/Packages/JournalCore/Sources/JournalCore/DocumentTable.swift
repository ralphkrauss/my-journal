import Foundation

/// GFM tables have one header row and single-line cells. Display wrapping does not add newlines to storage.
public struct DocumentTable: Codable, Equatable, Sendable {
    public var rows: [[[TextRun]]]
    public var alignments: [String?]
    public init(rows: [[[TextRun]]], alignments: [String?]) {
        self.rows = rows
        self.alignments = alignments
    }
    public var text: String {
        rows.map { row in row.map { $0.map(\.text).joined() }.joined(separator: "\t") }.joined(separator: "\n")
    }
    public var columnCount: Int { rows.map(\.count).max() ?? 0 }
    public mutating func replaceCell(row: Int, column: Int, runs: [TextRun]) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        rows[row][column] = runs.map { run in
            var result = run
            result.breakKind = nil
            result.text = run.text.replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            return result
        }
    }
}

public enum TableStructureAction: Sendable {
    case addRow, addColumn, deleteRow, deleteColumn, deleteTable, align(String)
}

extension DocumentTable {
    /// Returns false when the explicit deletion removes the table's final row or column.
    @discardableResult public mutating func apply(_ action: TableStructureAction, row: Int, column: Int) -> Bool {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return true }
        let width = columnCount
        for index in rows.indices where rows[index].count < width {
            rows[index] += Array(repeating: [], count: width - rows[index].count)
        }
        switch action {
        case .addRow:
            rows.insert(Array(repeating: [], count: columnCount), at: row + 1)
        case .addColumn:
            for index in rows.indices { rows[index].insert([], at: column + 1) }
            while alignments.count < columnCount - 1 { alignments.append(nil) }
            alignments.insert(nil, at: column + 1)
        case .deleteRow:
            rows.remove(at: row)
        case .deleteColumn:
            for index in rows.indices { rows[index].remove(at: column) }
            if alignments.indices.contains(column) { alignments.remove(at: column) }
        case .deleteTable:
            rows = []
        case .align(let value):
            guard ["left", "center", "right"].contains(value) else { return true }
            while alignments.count < columnCount { alignments.append(nil) }
            alignments[column] = value
        }
        return !rows.isEmpty && columnCount > 0
    }
}
