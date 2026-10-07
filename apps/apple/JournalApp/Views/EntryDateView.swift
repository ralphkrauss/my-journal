import JournalCore
import SwiftUI

struct EntryDateView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: JournalItem
    @State private var date: Date
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?

    init(entry: JournalItem) {
        self.entry = entry
        _date = State(initialValue: entry.date)
    }
    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    Form {
                        Section {
                            datePicker
                        } footer: {
                            if let error { errorText(error) }
                        }
                    }
                    .navigationTitle("Change Date").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { cancelButton }
                        ToolbarItem(placement: .confirmationAction) { saveButton }
                    }
                }
            #else
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Change Date").font(.title2.bold())
                            datePicker
                            if let error { errorText(error) }
                        }.padding(24)
                    }
                    Divider()
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 16) {
                                saveButton
                                cancelButton
                            }
                        } else {
                            HStack {
                                cancelButton
                                Spacer()
                                saveButton
                            }
                        }
                    }.padding()
                }
                .frame(idealWidth: 360, idealHeight: 260)
            #endif
        }
        .interactiveDismissDisabled(busy)
        .onDisappear { operation?.cancel() }
        .onValueChange(of: model.locked) {
            if $0 {
                operation?.cancel()
                dismiss()
            }
        }
        .onValueChange(of: model.selectedID) {
            if $0 != entry.id {
                operation?.cancel()
                dismiss()
            }
        }
        .onValueChange(of: error) { value in
            if let value, !model.locked { JournalAccessibility.announce(value) }
        }
    }
    @ViewBuilder private var datePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text("Date").accessibilityHidden(true)
                DatePicker("Date", selection: $date, displayedComponents: [.date])
                    .labelsHidden().accessibilityLabel("Date")
            }.frame(maxWidth: .infinity, alignment: .leading).disabled(busy)
        } else {
            DatePicker("Date", selection: $date, displayedComponents: [.date]).disabled(busy)
        }
    }
    private func errorText(_ text: String) -> some View {
        Text(text).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
    }
    private var saveButton: some View {
        Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(busy || model.saveFailure)
    }
    private func save() {
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                try await model.changeEntryDate(entry.id, expectedDate: entry.date, to: date)
                dismiss()
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, !model.locked, model.selectedID == entry.id else { return }
                self.error = error.shown(.saving)
            }
        }
    }
}
