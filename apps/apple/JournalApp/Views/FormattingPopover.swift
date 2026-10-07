import SwiftUI

/// Formatting's contents: the Mac and iPad popover, and the iPhone's Format panel in place of the keyboard. It observes
/// only the formatting session, so styling doesn't redraw the window.
struct FormattingPopover: View {
    let editor: EditorActions
    @ObservedObject var session: FormattingSession
    /// Closes the popover or panel when a row that finishes the formatting is chosen, or Close.
    let close: () -> Void
    #if os(macOS)
        private let rowHeight: CGFloat = 30
    #else
        private let rowHeight: CGFloat = 44
    #endif

    var body: some View {
        #if os(iOS)
            // As Notes' Format panel: a “Format” title with a close button, then the rows, which scroll only when
            // they don't all fit (larger text, landscape).
            ViewThatFits(in: .vertical) {
                VStack(spacing: 0) {
                    header
                    rows
                }
                VStack(spacing: 0) {
                    header
                    ScrollViewReader { scroller in
                        ScrollView { rows.id(Self.firstRow) }.modifier(FlashesScrollIndicators())
                            // The panel is kept between uses; each opening starts at the top, with Bold and the
                            // headings in view.
                            .onValueChange(of: session.isPresented) { presented in
                                if presented { scroller.scrollTo(Self.firstRow, anchor: .top) }
                            }
                    }
                }
            }
            .buttonStyle(FormattingRowStyle())
        #else
            rows.buttonStyle(FormattingRowStyle()).frame(width: 250).fixedSize(horizontal: false, vertical: true)
                // Escape when the popover has keyboard focus (opened from the keyboard or with VoiceOver).
                .onExitCommand(perform: close)
        #endif
    }
    #if os(iOS)
        private static let firstRow = "first-row"
        private var header: some View {
            ZStack {
                Text("Format").font(.headline).accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Button(action: close) {
                        // A fixed size, as the system's close buttons: at larger text sizes only the rows grow.
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(
                            .secondary
                        )
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    #endif
    private var state: FormattingState { session.state }
    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                inline("Bold", text: Text("B").bold(), command: .bold, selected: state.bold)
                inline("Italic", text: Text("I").italic(), command: .italic, selected: state.italic)
                inline("Underline", text: Text("U").underline(), command: .underline, selected: state.underline)
                inline(
                    "Strikethrough", text: Text("S").strikethrough(), command: .strikethrough,
                    selected: state.strikethrough)
                inline(
                    "Inline Code", text: Text("<>").font(.system(.body, design: .monospaced)), command: .code,
                    selected: state.code)
            }.font(.title3)
            Divider().padding(.vertical, 4)
            style("Heading 1", kind: "heading", font: .title3.bold())
            style("Heading 2", kind: "subheading", font: .headline)
            style("Heading 3", kind: "heading3", font: .subheadline.bold())
            style("Paragraph", kind: "paragraph", font: .body)
            if let completion = state.taskCompletion {
                Button {
                    apply(.toggleTask)
                } label: {
                    rowLabel(completion == .on ? "Mark as Unchecked" : "Mark as Checked")
                }
            }
            Menu {
                ForEach(4...6, id: \.self) { level in
                    Button("Heading \(level)") { apply(.paragraph("heading\(level)")) }
                }
            } label: {
                rowLabel("More Headings", opensMenu: true)
            }.disabled(state.paragraph == "tableCell" || inCodeBlock)
            Divider().padding(.vertical, 4)
            style("Bulleted List", kind: "bullet", font: .body, symbol: "list.bullet")
            style("Numbered List", kind: "numbered", font: .body, symbol: "list.number")
            style("Checklist", kind: "task", font: .body, symbol: "checklist")
            style("Block Quote", kind: "quote", font: .body, symbol: "text.quote")
            // Always shown, dimmed where they don't apply, so the rows don't move as the caret does
            // (docs/design/list-indentation-2026-10-04.md).
            HStack {
                indentation(
                    "Decrease Indent", symbol: "decrease.indent", command: .outdent, enabled: state.indent.decrease)
                indentation(
                    "Increase Indent", symbol: "increase.indent", command: .indent, enabled: state.indent.increase)
            }
            if inCodeBlock {
                Button {
                    apply(.insert(""))
                } label: {
                    rowLabel("Exit Code Block")
                }
            }
            Menu {
                Button("Code Block") { apply(.insert("```\n\n```\n")) }
                Button("Horizontal Rule") { apply(.insert("---\n")) }
                Button("Table") { apply(.insert("|  |  |\n| --- | --- |\n|  |  |\n")) }
                Button(state.link.edit ? "Edit Link…" : "Add Link…") { apply(.linkDialog) }
                Button("Remove Link") { apply(.removeLink(nil)) }.disabled(!state.link.remove)
                Button("Image…") { apply(.imagePicker) }
            } label: {
                rowLabel("Insert", opensMenu: true)
            }
        }.padding(8)
    }
    private var inCodeBlock: Bool { state.paragraph == "codeBlock" }
    /// Indenting keeps the panel open, so an item can be moved several levels, as the inline styles do.
    private func indentation(_ title: String, symbol: String, command: EditorCommand, enabled: Bool) -> some View {
        Button {
            editor.performFormatting(command)
        } label: {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, minHeight: rowHeight).contentShape(Rectangle())
        }.disabled(!enabled).accessibilityLabel(title).help(title)
    }
    private func rowLabel(_ title: String, opensMenu: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            if opensMenu {
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
            .frame(minHeight: rowHeight).contentShape(Rectangle())
    }
    /// Applies a command that finishes the formatting, then closes. Link… and Image… open once it has closed.
    private func apply(_ command: EditorCommand) {
        switch command {
        case .linkDialog: editor.pendingPresentation = .link
        case .imagePicker: editor.pendingPresentation = .image
        default: editor.performFormatting(command)
        }
        close()
    }
    private func inline(_ label: String, text: Text, command: EditorCommand, selected: FormattingToggle) -> some View {
        Button {
            editor.performFormatting(command)
        } label: {
            HStack(spacing: 4) {
                text
                if selected == .mixed { Image(systemName: "minus").font(.caption2) }
            }.frame(maxWidth: .infinity, minHeight: rowHeight).contentShape(Rectangle())
                .background(
                    selected != .off ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }.disabled(inCodeBlock).accessibilityLabel(label).accessibilityValue(selected.rawValue.capitalized)
            .help(label)
    }
    private func style(_ label: String, kind: String, font: Font, symbol: String? = nil) -> some View {
        Button {
            apply(.paragraph(kind))
        } label: {
            HStack {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(label).font(font)
                Spacer(minLength: 0)
                if isCurrent(kind) { Image(systemName: "checkmark").font(.caption) }
            }.padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).contentShape(Rectangle())
        }.disabled(state.paragraph == "tableCell" || inCodeBlock)
            .accessibilityLabel(label).accessibilityAddTraits(isCurrent(kind) ? .isSelected : [])
    }
    /// Whether the selection is in this style; checked and unchecked items are both a checklist.
    private func isCurrent(_ kind: String) -> Bool {
        state.paragraph == kind || kind == "task" && state.paragraph == "checked"
    }
}

/// The Formatting button of the iPhone and iPad bars, shown selected while its popover or panel is open.
struct FormattingButton: View {
    @ObservedObject var session: FormattingSession
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Formatting", systemImage: "textformat")
        }
        .background {
            if session.isPresented { Circle().fill(Color.primary.opacity(0.12)).frame(width: 40, height: 40) }
        }
        .accessibilityAddTraits(session.isPresented ? .isSelected : [])
    }
}

/// When the rows don't fit, the indicator shows at once that the list scrolls (iOS 17 and later).
private struct FlashesScrollIndicators: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.scrollIndicatorsFlash(onAppear: true)
        } else {
            content
        }
    }
}

private struct FormattingRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }
    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false
        var body: some View {
            // A custom style draws its own disabled state: dimmed, as the system dims an unavailable control, and
            // without the hover highlight.
            configuration.label.opacity(isEnabled ? 1 : 0.3).background(
                isEnabled && (hovered || configuration.isPressed) ? Color.primary.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 4)
            ).onHover { hovered = $0 }
        }
    }
}
