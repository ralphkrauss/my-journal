import JournalCore
import SwiftUI

/// The table commands: one list, in one order, wherever they appear. The Mac cell menu, Format ▸ Table on the Mac and
/// the iPad, and the iPhone and iPad cell edit menu are all rendered from `groups`
/// (docs/design/1-1-settings-messages-editor.md §6.2).
enum TableMenu {
    struct Item {
        let id: String
        let title: String
        let action: TableStructureAction
        var isDestructive = false
        var isChecked = false
    }
    enum Entry {
        case item(Item)
        /// Alignment: Left, Center and Right, with the column's current one checked.
        case submenu(title: String, items: [Item])
    }
    /// The entries in groups; a divider goes between groups. `alignment` is the column's stored alignment; a column
    /// with none is drawn left aligned, so Left is the checked one.
    static func groups(alignment: String?) -> [[Entry]] {
        let current = alignment ?? "left"
        let alignments = ["left", "center", "right"].map { value in
            Item(
                id: "align-\(value)", title: value.capitalized, action: .align(value), isChecked: value == current)
        }
        return [
            [
                .item(Item(id: "addRow", title: "Add Row Below", action: .addRow)),
                .item(Item(id: "addColumn", title: "Add Column After", action: .addColumn)),
                .submenu(title: "Alignment", items: alignments),
            ],
            [
                .item(Item(id: "deleteRow", title: "Delete Row", action: .deleteRow, isDestructive: true)),
                .item(Item(id: "deleteColumn", title: "Delete Column", action: .deleteColumn, isDestructive: true)),
                .item(Item(id: "deleteTable", title: "Delete Table", action: .deleteTable, isDestructive: true)),
            ],
        ]
    }
}

/// Format ▸ Table on the Mac and the iPad.
struct TableMenuContent: View {
    let alignment: String?
    let perform: (TableStructureAction) -> Void

    var body: some View {
        let groups = Array(TableMenu.groups(alignment: alignment).enumerated())
        ForEach(groups, id: \.offset) { index, group in
            if index > 0 { Divider() }
            let entries = Array(group.enumerated())
            ForEach(entries, id: \.offset) { _, entry in
                switch entry {
                case .item(let item):
                    Button(item.title, role: item.isDestructive ? .destructive : nil) { perform(item.action) }
                case .submenu(let title, let items):
                    Menu(title) {
                        ForEach(items, id: \.id) { item in
                            Toggle(
                                item.title, isOn: Binding(get: { item.isChecked }, set: { _ in perform(item.action) }))
                        }
                    }
                }
            }
        }
    }
}

extension TablePresentation {
    /// The stored alignment of a column, "left" when it has none.
    static func alignment(of table: DocumentTable?, column: Int) -> String {
        guard let table, table.alignments.indices.contains(column) else { return "left" }
        return table.alignments[column] ?? "left"
    }
}
