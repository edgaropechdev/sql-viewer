import AppKit
import MySQLClient
import SwiftUI

/// Spreadsheet-style result grid on top of a view-based NSTableView, which
/// recycles cells and stays fast at tens of thousands of rows (SwiftUI's
/// `Table` does not).
struct ResultGridView: NSViewRepresentable {
    struct Sort: Equatable {
        var column: Int
        var ascending: Bool
    }

    var columns: [Column]
    var rows: [[String?]]
    var sort: Sort?
    /// Non-nil makes headers clickable.
    var onSort: ((Sort) -> Void)?
    /// Per-column editability; cells are edited with a double-click.
    var canEdit: ((Int) -> Bool)?
    var onEdit: ((_ row: Int, _ column: Int, _ value: String?) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = GridTableView()
        table.coordinator = coordinator
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 20
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))

        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        coordinator.table = table
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(with: self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        weak var table: NSTableView?
        private var grid = ResultGridView(columns: [], rows: [])
        private var editingCell: (row: Int, column: Int)?
        private var isSyncingSort = false

        /// Longer values are shown truncated and must be edited with SQL.
        static let inlineLimit = 500
        private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        private static let nullFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        private static let cellID = NSUserInterfaceItemIdentifier("cell")

        func update(with newGrid: ResultGridView) {
            guard let table else { return }
            let columnsChanged = newGrid.columns != grid.columns
            grid = newGrid
            if columnsChanged {
                rebuildColumns(in: table)
            }
            syncSortIndicator(in: table)
            // Reloading would end an in-progress edit.
            if editingCell == nil {
                table.reloadData()
            }
        }

        private func rebuildColumns(in table: NSTableView) {
            editingCell = nil
            for column in table.tableColumns.reversed() {
                table.removeTableColumn(column)
            }
            for (index, column) in grid.columns.enumerated() {
                let tableColumn = NSTableColumn(identifier: .init(String(index)))
                tableColumn.title = column.name
                tableColumn.minWidth = 40
                tableColumn.width = estimatedWidth(of: index)
                if grid.onSort != nil {
                    tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: true)
                }
                table.addTableColumn(tableColumn)
            }
            table.scrollRowToVisible(0)
        }

        private func estimatedWidth(of column: Int) -> CGFloat {
            let charWidth: CGFloat = 7.3
            let sampleLength = grid.rows.prefix(100).reduce(0) { longest, row in
                max(longest, min(row[column]?.count ?? 4, 60))
            }
            let header = CGFloat(grid.columns[column].name.count) * charWidth + 30
            return min(max(header, CGFloat(sampleLength) * charWidth + 16, 60), 380)
        }

        private func syncSortIndicator(in table: NSTableView) {
            let descriptors = grid.sort.map { [NSSortDescriptor(key: String($0.column), ascending: $0.ascending)] } ?? []
            guard table.sortDescriptors != descriptors else { return }
            isSyncingSort = true
            table.sortDescriptors = descriptors
            isSyncingSort = false
        }

        // MARK: Data source & delegate

        func numberOfRows(in tableView: NSTableView) -> Int {
            grid.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Int(tableColumn.identifier.rawValue) else { return nil }
            let cell = tableView.makeView(withIdentifier: Self.cellID, owner: self) as? NSTableCellView ?? makeCell()
            configure(cell.textField!, value: grid.rows[row][column], kind: grid.columns[column].kind)
            return cell
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isSyncingSort, let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key, let column = Int(key) else { return }
            grid.onSort?(Sort(column: column, ascending: descriptor.ascending))
        }

        private func makeCell() -> NSTableCellView {
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.delegate = self
            let cell = NSTableCellView()
            cell.identifier = Self.cellID
            cell.textField = field
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func configure(_ field: NSTextField, value: String?, kind: Column.Kind) {
            field.isEditable = false
            field.alignment = kind == .numeric ? .right : .left
            if let value {
                field.font = Self.font
                field.textColor = .labelColor
                field.stringValue = Self.displayString(value)
            } else {
                field.font = Self.nullFont
                field.textColor = .tertiaryLabelColor
                field.stringValue = "NULL"
            }
        }

        private static func displayString(_ value: String) -> String {
            let clipped = value.count > inlineLimit ? value.prefix(inlineLimit) + "…" : Substring(value)
            return clipped.replacingOccurrences(of: "\r\n", with: "↵")
                .replacingOccurrences(of: "\n", with: "↵")
                .replacingOccurrences(of: "\t", with: " ")
        }

        // MARK: Inline editing

        private func isEditable(row: Int, column: Int) -> Bool {
            guard grid.canEdit?(column) == true, grid.onEdit != nil else { return false }
            let value = grid.rows[row][column] ?? ""
            return value.count <= Self.inlineLimit && !value.contains(where: \.isNewline)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            let column = sender.clickedColumn
            guard row >= 0, column >= 0,
                  let modelColumn = Int(sender.tableColumns[column].identifier.rawValue),
                  isEditable(row: row, column: modelColumn),
                  let field = (sender.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView)?.textField
            else {
                if row >= 0, column >= 0 { NSSound.beep() }
                return
            }
            editingCell = (row, modelColumn)
            field.isEditable = true
            field.font = Self.font
            field.textColor = .labelColor
            field.stringValue = grid.rows[row][modelColumn] ?? ""
            sender.window?.makeFirstResponder(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), let row = editingCell?.row else { return false }
            editingCell = nil
            control.abortEditing()
            table?.reloadData(forRowIndexes: [row], columnIndexes: IndexSet(integersIn: 0..<(table?.numberOfColumns ?? 0)))
            table?.window?.makeFirstResponder(table)
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, let (row, column) = editingCell else { return }
            editingCell = nil
            field.isEditable = false
            let original = grid.rows[row][column]
            let edited = field.stringValue
            // Leaving a NULL cell empty keeps it NULL; "Establecer NULL" is explicit.
            if edited == original || (original == nil && edited.isEmpty) {
                configure(field, value: original, kind: grid.columns[column].kind)
                return
            }
            grid.onEdit?(row, column, edited)
            table?.window?.makeFirstResponder(table)
        }

        // MARK: Copy & context menu

        func copySelection(includeHeaders: Bool = false) {
            guard let table else { return }
            let rows = table.selectedRowIndexes.map { grid.rows[$0] }
            guard !rows.isEmpty else { return }
            let order = table.tableColumns.compactMap { Int($0.identifier.rawValue) }
            var lines = rows.map { row in order.map { row[$0] ?? "NULL" }.joined(separator: "\t") }
            if includeHeaders {
                lines.insert(order.map { grid.columns[$0].name }.joined(separator: "\t"), at: 0)
            }
            setPasteboard(lines.joined(separator: "\n"))
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, table.clickedRow >= 0 else { return }
            let row = table.clickedRow
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes([row], byExtendingSelection: false)
            }
            if table.clickedColumn >= 0, let column = Int(table.tableColumns[table.clickedColumn].identifier.rawValue) {
                menu.addItem(item("Copiar valor") { [weak self] in
                    self?.setPasteboard(self?.grid.rows[row][column] ?? "NULL")
                })
                if grid.canEdit?(column) == true, grid.columns[column].isNullable, grid.rows[row][column] != nil {
                    menu.addItem(item("Establecer NULL") { [weak self] in
                        self?.grid.onEdit?(row, column, nil)
                    })
                }
                menu.addItem(.separator())
            }
            menu.addItem(item("Copiar filas") { [weak self] in self?.copySelection() })
            menu.addItem(item("Copiar filas con encabezados") { [weak self] in self?.copySelection(includeHeaders: true) })
        }

        private func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(ClosureTarget.invoke), keyEquivalent: "")
            let target = ClosureTarget(action)
            item.target = target
            item.representedObject = target  // menu items hold targets weakly
            return item
        }

        private func setPasteboard(_ string: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }
}

final class GridTableView: NSTableView {
    weak var coordinator: ResultGridView.Coordinator?

    /// Edit ▸ Copy (⌘C) copies the selected rows as TSV.
    @objc func copy(_ sender: Any?) {
        coordinator?.copySelection()
    }
}

private final class ClosureTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
