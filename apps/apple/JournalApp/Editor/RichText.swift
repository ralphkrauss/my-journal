import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
    typealias PlatformImage = NSImage
#else
    import UIKit
    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
    typealias PlatformImage = UIImage
#endif

enum EditorCommand {
    case source, strikethrough, code, insert(String), linkDialog, imagePicker, toggleTask, indent, outdent
    case bold, italic, underline, paragraph(String), link(String, text: String? = nil), image(DocumentBlock), focus
    /// Changes the address of the link `link` names, and its text when `text` is given and differs
    /// (docs/design/build-18-fixes-2026-10-06.md §2.4).
    case editLink(EditableLink, address: String, text: String?)
    /// Takes the links the range touches off their text, or those at the selection when there is no range.
    case removeLink(NSRange?)
}
/// What the formatting popover or panel shows, and whether it's shown. Only the formatting controls observe it, so
/// opening, styling and closing don't redraw the window or the menu bar.
@MainActor
final class FormattingSession: ObservableObject {
    /// The styles at the current selection.
    @Published private(set) var state = FormattingState()
    /// The Formatting popover (Mac, iPad) or the Format panel in place of the keyboard (iPhone) is shown.
    @Published private(set) var isPresented = false
    func update(_ state: FormattingState) {
        if self.state != state { self.state = state }
    }
    func setPresented(_ presented: Bool) {
        if isPresented != presented { isPresented = presented }
    }
}

@MainActor
final class EditorActions: ObservableObject {
    #if os(iOS)
        /// The Formatting button in the bottom bar, where the iPad popover points when it's opened from there.
        weak var formattingToolbarAnchor: UIView?
        /// Shows the Formatting popover or panel, or closes it when it's shown; `anchor` is the button used.
        var toggleFormatting: ((_ anchor: UIView?) -> Void)?
        /// Commits an input method's composition before the keyboard makes way for the Format panel.
        var commitComposition: (() -> Void)?
        /// The text view being edited, the entry's or a table cell's, if any.
        var focusedTextInput: (() -> UITextView?)?
        /// The Format panel, shown by the text views in place of the keyboard while it's open (iPhone).
        var formattingInputView: UIView?
        var owningWindow: (() -> UIWindow?)?
        /// Writing that was under way when its editor was replaced (such as a rotation into the split view), so the
        /// replacement editor continues at the same place with the keyboard up. Only in the visit the writing began
        /// in: an entry opened again, however soon, opens for reading.
        var interruptedWriting: (itemID: UUID, selection: NSRange, time: Date, visit: Int)?
        /// Counts the person's moves between entries: going Back, choosing or opening one. A layout change isn't one.
        private(set) var entryVisit = 0
        /// The person left the open entry or opened another, so writing interrupted before doesn't continue.
        func entryVisitEnded() {
            entryVisit += 1
            interruptedWriting = nil
        }
        /// Offers interrupted writing to the most recently shown editor.
        var continueWriting: (() -> Void)?
    #endif
    var isEditing: (() -> Bool)?
    var toggleSource: (() -> Void)?
    /// Shows the system find navigator for the open entry (iPhone and iPad).
    var findInEntry: (() -> Void)?
    /// Applies a table command from Format ▸ Table to the cell being edited.
    var tableAction: ((TableStructureAction) -> Void)?
    var handler: ((EditorCommand) -> Void)?
    var beginFormatting: (() -> ((EditorCommand) -> Void)?)?
    private var formattingHandler: ((EditorCommand) -> Void)?
    var selectionText: (() -> String)?
    var selectionStyle: (() -> FormattingState)?
    /// The formatting popover's or panel's state, observed only by the formatting controls.
    let formatting = FormattingSession()
    var formattingState: FormattingState { formatting.state }
    /// Closes the formatting popover or panel; `refocus` returns keyboard focus to where it was. Set while shown.
    var closeFormatting: ((_ refocus: Bool) -> Void)?
    /// The person moved the selection or typed while the popover or panel is shown (not a formatting command).
    var formattingSelectionMoved: (() -> Void)?
    /// Set while a formatting command runs, so the selection change it makes isn't taken for the person's own.
    private(set) var performingFormatting = false
    private var formattingRefreshPending = false
    @Published var linkText = ""
    /// The link Edit Link… was chosen for, captured with the selection; nil while adding a link.
    @Published var editingLink: EditableLink?
    /// Which link commands apply to the caret or selection, for the menu bar.
    @Published var caretLink = LinkAvailability()
    /// The link at the selection, nil in Markdown source, in a table cell and where there is none.
    var linkAtSelection: (() -> EditableLink?)?
    @Published var searchRequested = false
    @Published var requestLink = false
    /// Some text in the entry has keyboard focus. Set with `setEditing(_:by:)` by the focused view itself (the title,
    /// the body or a table): moving between them, one can begin before the other ends. A view that leaves the screen
    /// without ending is forgotten with `forget(_:)`, and one that no longer exists drops out, so the Done checkmark
    /// never outlives the writing it belongs to (docs/design/sync-now-and-done.md).
    @Published private(set) var editing = false
    private struct FocusedView {
        weak var view: AnyObject?
    }
    private var focusedViews: [ObjectIdentifier: FocusedView] = [:]
    func setEditing(_ active: Bool, by view: AnyObject) {
        focusedViews[ObjectIdentifier(view)] = active ? FocusedView(view: view) : nil
        publishEditing()
    }
    /// Forgets `view`, which is leaving the screen, possibly during a view update: the change is published after it.
    func forget(_ view: AnyObject) {
        guard focusedViews.removeValue(forKey: ObjectIdentifier(view)) != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.publishEditing() }
    }
    /// Drops views that no longer exist or have left their window, such as a table torn down while one of its cells
    /// was focused, or the previous entry's editor once another one appears.
    func forgetDeparted() {
        DispatchQueue.main.async { [weak self] in self?.publishEditing() }
    }
    private func publishEditing() {
        focusedViews = focusedViews.filter { Self.isShown($0.value.view) }
        let active = !focusedViews.isEmpty
        if editing != active { editing = active }
    }
    private static func isShown(_ view: AnyObject?) -> Bool {
        guard let view else { return false }
        #if os(iOS)
            return (view as? UIView).map { $0.window != nil } ?? true
        #else
            return (view as? NSView).map { $0.window != nil } ?? true
        #endif
    }
    #if os(iOS)
        /// Set while Done ends editing, or a focused title is about to leave the screen. UIKit offers the keyboard to
        /// the enclosing text view when the title gives it up; the body declines it meanwhile. Tapping the body or
        /// Return in the title still moves focus.
        private(set) var endingEditing = false
        /// Runs `resign` with the body declining the keyboard.
        func whileEndingEditing(_ resign: () -> Void) {
            let wasEnding = endingEditing
            endingEditing = true
            resign()
            endingEditing = wasEnding
        }
        /// Done: ends editing in the title, the body or a table, so the entry returns to reading.
        func finishEditing() {
            let responders = focusedViews.values.compactMap { $0.view as? UIResponder }
            let focused = responders.first(where: { $0.isFirstResponder }) as? UIView
            let edited: UIView? = focused ?? focusedTextInput?() ?? responders.first as? UIView
            whileEndingEditing {
                for responder in responders where responder.isFirstResponder {
                    responder.resignFirstResponder()
                }
                // A table cell is focused inside its grid, which is what registered.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            focusedViews = [:]
            publishEditing()
            if let edited, edited.window != nil {
                UIAccessibility.post(notification: .layoutChanged, argument: edited)
            }
        }
    #endif
    /// True while a table cell has keyboard focus, so table commands can be offered.
    @Published var editingTable = false
    /// The alignment of the focused table cell's column, whose checkmark Format ▸ Table shows; nil outside a table.
    @Published var tableAlignment: String?
    @Published var requestImage = false
    /// Whether the caret is on a checked (true) or unchecked (false) task, for Mark as Checked; nil elsewhere.
    @Published var caretTaskChecked: Bool?
    /// Whether Format ▸ Increase and Decrease Indent apply to the selection (ListIndentation.swift).
    @Published var caretIndentation = ListIndentation.Availability()
    /// Where Insert Image takes the picture from; the photo library unless the person chose otherwise.
    enum ImageSource { case photos, camera, files }
    var imageSource: ImageSource = .photos
    /// Starts inserting an image from `source` at the captured selection.
    func insertImage(from source: ImageSource) {
        imageSource = source
        captureFormatting()
        requestImage = true
    }
    @Published var sourceMode = false
    enum Presentation { case link, image }
    var pendingPresentation: Presentation?
    /// The formatting popover or panel closed. Opens Add Link or the image picker when one was chosen in it, for the
    /// selection there is now; `refocus` returns keyboard focus to the text, when the person closed it themselves.
    func finishPresentation(refocus: Bool) {
        formatting.setPresented(false)
        closeFormatting = nil
        formattingSelectionMoved = nil
        guard let next = pendingPresentation else {
            if refocus { handler?(.focus) }
            return
        }
        pendingPresentation = nil
        switch next {
        case .link:
            prepareLink()
            presentLink()
        case .image:
            imageSource = .photos
            requestImage = true
        }
    }
    func openLinkFromKeyboard() {
        guard isEditing?() == true else { return }
        prepareLink()
        presentLink()
    }
    /// Add Link appears at once, without the sheet's animation, as the formatting controls do.
    private func presentLink() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { requestLink = true }
    }
    /// Add Link applies to the selection as it is when it opens.
    private func prepareLink() {
        captureFormatting()
        editingLink = linkAtSelection?()
        linkText = editingLink?.text ?? selectionText?() ?? ""
    }
    /// Remembers the selection for commands that act after focus has moved, and reads its styles.
    func captureFormatting() {
        formattingHandler = beginFormatting?()
        formatting.update(selectionStyle?() ?? FormattingState())
        let source = formatting.state.sourceMode
        if sourceMode != source { sourceMode = source }
    }
    /// Prepares the formatting popover or panel before it's shown.
    func beginFormattingPresentation() {
        captureFormatting()
        formatting.setPresented(true)
    }
    func performFormatting(_ command: EditorCommand) {
        if case .linkDialog = command {
            prepareLink()
            presentLink()
            return
        }
        if case .imagePicker = command {
            // Image… in the panel and the Format menu is the photo library; the camera and Files are chosen from
            // the bars' own menus.
            imageSource = .photos
            requestImage = true
            return
        }
        performingFormatting = true
        defer { performingFormatting = false }
        if formatting.isPresented, isEditing?() == true, let handler {
            // While the popover or panel is shown, commands act on the selection as it is now.
            handler(command)
        } else {
            formattingHandler?(command)
        }
        formatting.update(selectionStyle?() ?? FormattingState())
    }
    /// The selection or text changed while the popover or panel may be shown: its checkmarks and toggles follow, at
    /// most once per turn of the run loop.
    func formattingSelectionChanged() {
        guard formatting.isPresented else { return }
        if !performingFormatting { formattingSelectionMoved?() }
        guard !formattingRefreshPending else { return }
        formattingRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.formattingRefreshPending = false
            guard self.formatting.isPresented else { return }
            self.formatting.update(self.selectionStyle?() ?? FormattingState())
        }
    }
    func endFormatting() {
        closeFormatting?(false)
        formattingHandler = nil
        pendingPresentation = nil
        requestImage = false
    }
    func perform(_ command: EditorCommand) { handler?(command) }
    /// Switches the whole entry between Markdown source and preview, whether or not the editor has focus.
    func toggleSourceMode() {
        endFormatting()
        toggleSource?()
    }
}
extension NSAttributedString.Key {
    static let journalKind = Self("JournalBlockKind")
    static let journalBlockID = Self("JournalBlockID")
    static let journalImage = Self("JournalImage")
    static let journalStructuredBlock = Self("JournalStructuredBlock")
    static let journalBlockMetadata = Self("JournalBlockMetadata")
    static let journalBreakKind = Self("JournalBreakKind")
    static let journalLinkTitle = Self("JournalLinkTitle")
    static let journalRawHTML = Self("JournalRawHTML")
    static let journalInertLink = Self("JournalInertLink")
    /// Marks a rule's hidden character (RichText.ruleCharacter).
    static let journalMarker = Self("JournalMarker")
}
@MainActor
enum RichText {
    static func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> PlatformFont {
        let base = PlatformFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        #if os(macOS)
            return italic ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) : base
        #else
            let descriptor =
                italic
                ? base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.traitItalic))
                    ?? base.fontDescriptor : base.fontDescriptor
            return UIFont(descriptor: descriptor, size: size)
        #endif
    }
    /// The column a list item's bullet, number or checkbox sits in; its text starts after it, and wrapped lines
    /// line up with that text. One width for every kind of list, so they line up with each other, and it grows
    /// with the text (docs/design/checklists-2026-10-03.md).
    nonisolated static func listColumn(size: CGFloat) -> CGFloat { (size * 1.5).rounded() }
    /// How far in from the body text a list starts: its first-level marker sits this far in, and the content of its
    /// items moves in with it. The quote indent, so a marker lines up with a quote's text, and fixed rather than
    /// scaled, so large text keeps its width (docs/design/client-only-mac-lists-markdown-2026-10-05.md). Only the
    /// presentation moves; the Markdown is unchanged.
    static let listInset = BlockDecorations.quoteIndent
    /// How many list levels are drawn further in at `size`: as many columns as fit in 160 points, so deep nesting at
    /// a large text size still leaves its text room on the line. Increase Indent goes no deeper (ListIndentation).
    nonisolated static func visibleNestingLevels(size: CGFloat) -> Int { max(1, Int(160 / listColumn(size: size))) }
    /// How far list `levels` deep moves in: a column per level, up to `visibleNestingLevels`.
    nonisolated static func nestingIndent(levels: Int, size: CGFloat) -> CGFloat {
        CGFloat(min(levels, visibleNestingLevels(size: size))) * listColumn(size: size)
    }
    /// Blocks drawn in a bold font by their style. That weight isn't the Bold format: it isn't saved as bold and
    /// doesn't turn on the Bold button.
    nonisolated static let boldBlockKinds: Set<String> = [
        "heading", "subheading", "heading3", "heading4", "heading5", "heading6", "tableHeader",
    ]
    static func attributes(kind: String, size: CGFloat, run: TextRun = .init("")) -> [NSAttributedString.Key: Any] {
        let heading = boldBlockKinds.contains(kind)
        let pointSize =
            kind == "heading" ? size * 1.4 : kind == "subheading" ? size * 1.2 : kind == "heading3" ? size * 1.1 : size
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 10
        style.lineSpacing = 3
        if kind == "quote" {
            // The quote bar sits in this indent.
            style.firstLineHeadIndent = BlockDecorations.quoteIndent
            style.headIndent = BlockDecorations.quoteIndent
        }
        if ["codeBlock", "html"].contains(kind) {
            style.paragraphSpacing = 0
            style.firstLineHeadIndent = BlockDecorations.codeInset
            style.headIndent = BlockDecorations.codeInset
            style.tailIndent = -BlockDecorations.codeInset
        }
        if ListIndentation.kinds.contains(kind) {
            // The bullet, number or checkbox is drawn in the column before the text (ListLayout.swift), which
            // starts at the list inset.
            let indent = listInset + listColumn(size: size)
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(
                size: pointSize, bold: run.bold || heading, italic: run.italic),
            .foregroundColor: PlatformColor.labelColorCompat,
            .paragraphStyle: style, .journalKind: kind,
        ]
        if ["codeBlock", "html"].contains(kind) {
            attributes[.font] = PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        attributes.merge(ListAccessibility.attributes(kind: kind)) { $1 }
        if let kind = run.breakKind { attributes[.journalBreakKind] = kind }
        if let title = run.linkTitle { attributes[.journalLinkTitle] = title }
        if run.rawHTML { attributes[.journalRawHTML] = true }
        if run.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if run.code {
            attributes[.journalCode] = 1
            attributes[.font] = PlatformFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
            attributes[.backgroundColor] = BlockDecorations.codeFill
        }
        if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let link = run.link, let url = URL(string: link),
            ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
        {
            attributes[.link] = url
        } else if let link = run.link {
            attributes[.journalInertLink] = link
        }
        return attributes
    }
    /// `metadata` is the block already encoded, so a long paragraph is encoded once rather than once per run.
    static func blockAttributes(
        _ block: DocumentBlock, size: CGFloat, run: TextRun = TextRun(""), metadata: Data? = nil
    ) -> [NSAttributedString.Key: Any] {
        var result = attributes(kind: block.kind, size: size, run: run)
        if let data = metadata ?? (try? JournalCoding.encoder().encode(block)) { result[.journalBlockMetadata] = data }
        result[.journalBlockID] = block.id.uuidString
        if let levels = block.listIndents, !levels.isEmpty {
            result.merge(ListAccessibility.attributes(kind: block.kind, number: block.listNumber, level: levels.count))
            {
                $1
            }
        }
        if let prefix = block.markdownPrefix, !prefix.isEmpty,
            let style = (result[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
        {
            // Each list level moves in by one list column, so a nested item's marker lines up with its parent's
            // text however many spaces the Markdown uses; other prefixes, such as a quote's "> ", by half an em
            // per character. Content inside a list item that isn't an item itself, such as its second paragraph,
            // moves in by the list inset too, as the item's text does, so it stays aligned with that text.
            let levels = block.listIndents ?? []
            let other = max(0, prefix.count - levels.reduce(0, +))
            let inset = !levels.isEmpty && !ListIndentation.kinds.contains(block.kind) ? listInset : 0
            let indent = nestingIndent(levels: levels.count, size: size) + CGFloat(other) * size * 0.5 + inset
            style.firstLineHeadIndent += indent
            style.headIndent += indent
            style.tabStops = style.tabStops.map {
                NSTextTab(textAlignment: $0.alignment, location: $0.location + indent, options: $0.options)
            }
            result[.paragraphStyle] = style
        }
        return result
    }
    /// How rendered blocks lay out their images: the width of the editor's text and which images are still loading.
    struct ImageLayout {
        var width: CGFloat = 620
        var loading: Set<UUID> = []
        var placeholderColor: PlatformColor?
        /// Pixels per point on the editor's screen, and the editor's pictures decoded at the size they are shown.
        var scale: CGFloat = 2
        var thumbnails: ImageThumbnails?
    }
    /// The editor's text for `document`. A whole entry (`endsText`) whose last block is a list item or quote ends
    /// with that item's own line break; a fragment placed into other text doesn't (ListEditing.swift).
    static func render(
        _ document: JournalDocument, size: CGFloat, images: [UUID: Data], sourceMode: Bool = false,
        layout: ImageLayout, endsText: Bool = true
    ) -> NSAttributedString {
        if sourceMode || document.requiresMarkdownSource {
            return MarkdownEditing.render(document.markdown, size: size)
        }
        return blocks(document, size: size, images: images, layout: layout, endsText: endsText)
    }
    /// Makes the first paragraph of `text` join the paragraph it is inserted into: it loses its own block, and any
    /// list marker, and takes on the block of the text around it.
    static func joinParagraph(_ text: NSMutableAttributedString) {
        let first = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        for marker in markerRanges(text, in: first).reversed() { text.deleteCharacters(in: marker) }
        let joined = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        text.enumerateAttribute(.attachment, in: joined) { value, part, _ in
            guard value == nil else { return }
            for key in [
                NSAttributedString.Key.journalKind, .journalBlockID, .journalBlockMetadata, .journalStructuredBlock,
                .journalListNumber, .journalOwnEnd,
            ] + ListAccessibility.keys {
                text.removeAttribute(key, range: part)
            }
        }
    }
    static func render(
        _ document: JournalDocument, size: CGFloat, images: [UUID: Data], sourceMode: Bool = false,
        width: CGFloat = 620,
        loadingImages: Set<UUID> = [], placeholderColor: PlatformColor? = nil, endsText: Bool = true
    )
        -> NSAttributedString
    {
        render(
            document, size: size, images: images, sourceMode: sourceMode,
            layout: ImageLayout(width: width, loading: loadingImages, placeholderColor: placeholderColor),
            endsText: endsText)
    }
    private static func blocks(
        _ document: JournalDocument, size: CGFloat, images: [UUID: Data], layout: ImageLayout, endsText: Bool
    ) -> NSAttributedString {
        let width = layout.width
        let result = NSMutableAttributedString(string: "")
        let blocks = document.blocks.isEmpty ? [DocumentBlock()] : document.blocks
        var number = 0
        for (index, block) in blocks.enumerated() {
            let start = result.length
            if block.kind == "numbered" { number += 1 } else { number = 0 }
            let metadata = try? JournalCoding.encoder().encode(block)
            let base = blockAttributes(block, size: size, metadata: metadata)
            if block.kind == "table" {
                result.append(TablePresentation.render(block, width: width, size: size))
            } else if block.kind == "image" {
                let attachment = ImagePresentation.attachment(
                    block, images: images, loading: layout.loading, size: size, width: width,
                    placeholderColor: layout.placeholderColor, scale: layout.scale, thumbnails: layout.thumbnails)
                let string = NSMutableAttributedString(attachment: attachment)
                // The picture's line is spaced like a paragraph, so the next block starts as far below it as the
                // picture starts below the block before it. Nesting doesn't indent it; it is sized to the full width.
                if let style = attributes(kind: block.kind, size: size)[.paragraphStyle] {
                    string.addAttribute(
                        .paragraphStyle, value: style, range: NSRange(location: 0, length: string.length))
                }
                if let metadata {
                    string.addAttribute(
                        .journalImage, value: metadata, range: NSRange(location: 0, length: string.length))
                }
                result.append(string)
            } else if ["codeBlock", "html"].contains(block.kind) {
                let text = block.runs.map(\.text).joined()
                result.append(NSAttributedString(string: text.isEmpty ? "\n" : text, attributes: base))
            } else {
                result.append(
                    textBlock(block, base: base, metadata: metadata, size: size, images: images, layout: layout))
            }
            // Code usually ends with its own line break, which then separates it from the next block.
            let endsWithBreak =
                ["codeBlock", "html"].contains(block.kind) && result.length > start && result.string.hasSuffix("\n")
            if index < blocks.count - 1, !endsWithBreak {
                result.append(NSAttributedString(string: "\n", attributes: base))
            } else if index == blocks.count - 1, endsText, ListMarkers.itemKinds.contains(block.kind) {
                var end = base
                end[.journalOwnEnd] = true
                result.append(NSAttributedString(string: "\n", attributes: end))
            }
            if result.length > start {
                if ["codeBlock", "html"].contains(block.kind), let data = metadata {
                    result.addAttribute(
                        .journalStructuredBlock, value: data,
                        range: NSRange(location: start, length: result.length - start))
                }
                result.addAttributes(
                    [.journalKind: block.kind, .journalBlockID: block.id.uuidString],
                    range: NSRange(location: start, length: result.length - start))
                if block.kind == "numbered" {
                    numbering(
                        result, range: NSRange(location: start, length: result.length - start),
                        number: block.listNumber ?? number, size: size)
                }
                let afterBox = index > 0 && ["codeBlock", "html", "table"].contains(blocks[index - 1].kind)
                let isCode = ["codeBlock", "html"].contains(block.kind)
                if index > 0, afterBox || isCode {
                    // Only the block's first line moves down; a code block's own lines stay together.
                    let first = (result.string as NSString).paragraphRange(for: NSRange(location: start, length: 0))
                    // A code block's background reaches 6 points above its text, so it needs that much more room.
                    spaceAfterCode(
                        result,
                        range: NSIntersectionRange(first, NSRange(location: start, length: result.length - start)),
                        spacing: (afterBox ? 12 : 0) + (isCode ? 6 : 0))
                }
            }
        }
        if blocks.contains(where: { $0.kind == "numbered" }) {
            alignNumberedLists(result, around: NSRange(location: 0, length: result.length), size: size)
        }
        return result
    }
    /// A paragraph, heading, list item, quote or rule: its text, with no characters for markers.
    private static func textBlock(
        _ block: DocumentBlock, base: [NSAttributedString.Key: Any], metadata: Data?, size: CGFloat,
        images: [UUID: Data], layout: ImageLayout
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if block.kind == "rule" { result.append(ruleCharacter(attributes: base)) }
        for run in block.runs {
            if run.imageSource != nil {
                let image = NSMutableAttributedString(
                    attributedString: inlineImage(run, size: size, images: images, layout: layout))
                image.addAttributes(base, range: NSRange(location: 0, length: image.length))
                result.append(image)
                continue
            }
            result.append(
                NSAttributedString(
                    string: run.breakKind == nil ? run.text : "\u{2028}",
                    attributes: blockAttributes(block, size: size, run: run, metadata: metadata)))
        }
        return result
    }
    /// The one hidden character of a rule's line, which is the rule itself, as U+FFFC is a picture. Reading skips it
    /// by `.journalMarker`. List items and quotes have no such characters: their markers are drawn (ListLayout.swift).
    static func ruleCharacter(attributes base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attributes = base
        attributes[.journalMarker] = true
        attributes[.foregroundColor] = PlatformColor.clear
        return NSAttributedString(string: "—", attributes: attributes)
    }
    /// Gives a numbered item in `range` its number, and its first line room for a number wider than the list column,
    /// which would otherwise overlap the text.
    static func numbering(_ text: NSMutableAttributedString, range: NSRange, number: Int, size: CGFloat) {
        text.addAttribute(.journalListNumber, value: number, range: range)
        ListAccessibility.renumber(text, range: range, number: number)
        let font = ListMarkers.font(size: size)
        let width = ("\(number)." as NSString).size(withAttributes: [.font: font]).width
        let column = listColumn(size: size)
        guard width > column else { return }
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        text.enumerateAttribute(.paragraphStyle, in: range) { value, part, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.firstLineHeadIndent = style.headIndent - column + (width + space).rounded(.up)
            text.addAttribute(.paragraphStyle, value: style, range: part)
        }
    }
    /// The attributes of a list item's or quote's paragraph, its line break included.
    static func itemAttributes(_ block: DocumentBlock, number: Int?, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let text = NSMutableAttributedString(string: "\n", attributes: blockAttributes(block, size: size))
        if block.kind == "numbered" {
            numbering(text, range: NSRange(location: 0, length: 1), number: number ?? block.listNumber ?? 1, size: size)
        }
        return text.attributes(at: 0, effectiveRange: nil)
    }
    /// Leaves room below a code block's background or a table grid before the next block.
    static func spaceAfterCode(_ text: NSMutableAttributedString, range: NSRange, spacing: CGFloat = 12) {
        text.enumerateAttribute(.paragraphStyle, in: range) { value, part, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.paragraphSpacingBefore = spacing
            text.addAttribute(.paragraphStyle, value: style, range: part)
        }
    }
    struct NewlineAction {
        let range: NSRange
        let replacement: NSAttributedString
        let nextKind: String
        var typing: [NSAttributedString.Key: Any]? = nil
        /// Where the caret goes afterwards, when not at the end of the replacement.
        var caret: Int? = nil
    }
    static func newlineAction(_ text: NSAttributedString, selection: NSRange, size: CGFloat) -> NewlineAction? {
        guard !MarkdownEditing.isSource(text), selection.location <= text.length else { return nil }
        let source = text.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: selection.location, length: 0))
        // An empty last line has no characters of its own; the line break before it belongs to the previous block,
        // so its style must not make this line behave like, say, an empty list item.
        guard paragraph.length > 0 else { return nil }
        let line = paragraphContentRange(text.string, selection: NSRange(location: selection.location, length: 0))
        let attributes =
            paragraphAttributes(text, in: line) ?? text.attributes(at: paragraph.location, effectiveRange: nil)
        let kind = attributes[.journalKind] as? String ?? "paragraph"
        let headings = ["heading", "subheading", "heading3", "heading4", "heading5", "heading6"]
        if headings.contains(kind) {
            return headingReturn(text, selection: selection, attributes: attributes, kind: kind, size: size)
        }
        guard ListMarkers.itemKinds.contains(kind) else { return nil }
        let empty = content(text, in: line).length == 0
        if empty, selection.length == 0 {
            return leavingItem(text, paragraph: paragraph, attributes: attributes, size: size)
        }
        if selection.length == 0, selection.location == line.location, !empty {
            return itemAbove(text, paragraph: paragraph, attributes: attributes, size: size)
        }
        // The next item continues the formatting at the caret, not the item's first word.
        let style =
            selection.location > paragraph.location
            ? text.attributes(at: selection.location - 1, effectiveRange: nil) : attributes
        return itemLines(text, range: selection, lines: ["", ""], typing: style, size: size)
    }

    static func document(_ text: NSAttributedString) -> JournalDocument {
        // An attachment may share a native paragraph with text. Split around it
        // without dropping either adjacent text or its encrypted image reference.
        let source = text.string as NSString
        var blocks: [DocumentBlock] = []
        var position = 0
        while position < source.length {
            if let structured = structuredBlock(text, at: position) {
                blocks.append(structured.block)
                position = NSMaxRange(structured.range)
                continue
            }
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            var end = NSMaxRange(paragraph)
            while end > paragraph.location
                && ["\n", "\r"].contains(source.substring(with: NSRange(location: end - 1, length: 1)))
            { end -= 1 }
            // A code block may end inside a native paragraph; never read its characters twice.
            var start = max(position, paragraph.location)
            var foundImage = false
            for (index, block) in blockAttachments(text, in: NSRange(location: start, length: max(0, end - start))) {
                if index > start {
                    blocks +=
                        textDocument(text.attributedSubstring(from: NSRange(location: start, length: index - start)))
                        .blocks
                }
                blocks.append(block)
                foundImage = true
                start = index + 1
            }
            if end > start {
                blocks +=
                    textDocument(text.attributedSubstring(from: NSRange(location: start, length: end - start))).blocks
            } else if !foundImage, position <= paragraph.location {
                blocks.append(emptyBlock(text, paragraph: paragraph))
            }
            position = NSMaxRange(paragraph)
        }
        // A line break ends an empty paragraph after it, unless it is the last list item's own (ListLayout.swift).
        if blocks.isEmpty
            || source.length > 0 && source.substring(from: source.length - 1) == "\n" && !ListMarkers.hasOwnEnd(text)
        {
            blocks.append(DocumentBlock())
        }
        var seen = Set<UUID>()
        for index in blocks.indices {
            if !seen.insert(blocks[index].id).inserted {
                blocks[index].id = UUID()
                seen.insert(blocks[index].id)
            }
        }
        return JournalDocument(blocks: blocks)
    }
    /// The block of a paragraph that has only its line break: an empty list item or quote keeps its block, which
    /// its line break carries; any other empty line is a new empty paragraph, as before.
    private static func emptyBlock(_ text: NSAttributedString, paragraph: NSRange) -> DocumentBlock {
        guard paragraph.length > 0,
            ListMarkers.itemKinds.contains(
                text.attribute(.journalKind, at: paragraph.location, effectiveRange: nil) as? String ?? ""),
            var block = self.paragraph(text, content: NSRange(location: paragraph.location, length: 0)).first?.0
        else { return DocumentBlock() }
        if let raw = text.attribute(.journalBlockID, at: paragraph.location, effectiveRange: nil) as? String,
            let id = UUID(uuidString: raw)
        {
            block.id = id
        }
        return block
    }
    /// The images and tables in `range`, each with its position.
    private static func blockAttachments(_ text: NSAttributedString, in range: NSRange) -> [(Int, DocumentBlock)] {
        var result: [(Int, DocumentBlock)] = []
        text.enumerateAttribute(.attachment, in: range) { value, part, _ in
            guard value != nil else { return }
            for index in part.location..<NSMaxRange(part) {
                guard
                    let data =
                        (text.attribute(.journalImage, at: index, effectiveRange: nil)
                        ?? text.attribute(.journalTable, at: index, effectiveRange: nil)) as? Data,
                    let block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: data)
                else { continue }
                result.append((index, block))
            }
        }
        return result
    }
    private static func structuredBlock(_ text: NSAttributedString, at position: Int) -> (
        block: DocumentBlock, range: NSRange
    )? {
        // Most paragraphs aren't code; finding where "no code" ends would scan the rest of the entry.
        guard text.attribute(.journalStructuredBlock, at: position, effectiveRange: nil) != nil else { return nil }
        var range = NSRange()
        guard
            let data = text.attribute(
                .journalStructuredBlock, at: position, longestEffectiveRange: &range,
                in: NSRange(location: position, length: text.length - position)) as? Data,
            var block = try? JournalCoding.decoder().decode(DocumentBlock.self, from: data)
        else { return nil }
        var value = text.attributedSubstring(from: range).string
        let original = block.runs.map(\.text).joined()
        // Code that ends with a line break is rendered without a separate separator, so keep that break.
        if NSMaxRange(range) < text.length, value.hasSuffix("\n"), !original.hasSuffix("\n") { value.removeLast() }
        if value == "\n", original.isEmpty { value = "" }
        block.runs = [TextRun(value)]
        return (block, range)
    }
    private static func paragraphIdentity(_ text: NSAttributedString, range: NSRange) -> UUID? {
        var identity: UUID?
        text.enumerateAttribute(.journalBlockID, in: range) { value, _, stop in
            guard let raw = value as? String, let id = UUID(uuidString: raw) else { return }
            identity = id
            stop.pointee = true
        }
        return identity
    }
    static func textDocument(_ text: NSAttributedString) -> JournalDocument {
        let source = text.string as NSString
        var blocks: [DocumentBlock] = []
        var position = 0
        var seen = Set<UUID>()
        repeat {
            let range = source.paragraphRange(for: NSRange(location: position, length: 0))
            let end = min(NSMaxRange(range), source.length)
            var contentEnd = end
            while contentEnd > range.location
                && ["\n", "\r"].contains(source.substring(with: NSRange(location: contentEnd - 1, length: 1)))
            { contentEnd -= 1 }
            let content = NSRange(location: range.location, length: contentEnd - range.location)
            for (block, identity) in paragraph(text, content: content) {
                var block = block
                if let identity, let id = paragraphIdentity(text, range: identity), seen.insert(id).inserted {
                    block.id = id
                }
                blocks.append(block)
            }
            position = end
            if end == source.length { break }
        } while position < source.length
        if source.length > 0 && source.substring(from: source.length - 1) == "\n" && !ListMarkers.hasOwnEnd(text) {
            blocks.append(DocumentBlock())
        }
        return JournalDocument(blocks: blocks)
    }
    /// Reads one native paragraph, with the range each block takes its identity from. Its kind and metadata come
    /// from its first character that carries them, since text typed on iOS or pasted from elsewhere carries none;
    /// a rule's hidden character is never read as content.
    private static func paragraph(_ text: NSAttributedString, content: NSRange) -> [(DocumentBlock, NSRange?)] {
        // An empty paragraph has only its line break, which keeps the block it was rendered for.
        let attributes =
            paragraphAttributes(text, in: content)
            ?? (content.location < text.length ? text.attributes(at: content.location, effectiveRange: nil) : [:])
        var kind = attributes[.journalKind] as? String ?? "paragraph"
        let markers = markerRanges(text, in: content)
        let body = self.content(text, in: content)
        var block =
            (attributes[.journalBlockMetadata] as? Data).flatMap {
                try? JournalCoding.decoder().decode(DocumentBlock.self, from: $0)
            } ?? DocumentBlock()
        switch kind {
        case "image", "table":
            // Text typed where an image or table was keeps only the text, never another copy of the block.
            kind = "paragraph"
            block = DocumentBlock()
        case "rule":
            // Text written on or below a rule line is a paragraph of its own; the rule stays a rule.
            let runs = readRuns(body, range: NSRange(location: 0, length: body.length), kind: "paragraph")
            guard let marker = markers.first, marker.location == content.location else {
                return [(DocumentBlock(runs: runs), content)]
            }
            block.kind = kind
            block.runs = []
            let rest = NSRange(location: NSMaxRange(marker), length: NSMaxRange(content) - NSMaxRange(marker))
            return runs.isEmpty ? [(block, marker)] : [(block, marker), (DocumentBlock(runs: runs), rest)]
        default: break
        }
        block.kind = kind
        block.runs = readRuns(body, range: NSRange(location: 0, length: body.length), kind: kind)
        return [(block, content)]
    }
    /// The attributes of the first character in `range` that belongs to a block, or nil when none does.
    static func paragraphAttributes(_ text: NSAttributedString, in range: NSRange) -> [NSAttributedString.Key: Any]? {
        var result: [NSAttributedString.Key: Any]?
        text.enumerateAttribute(.journalKind, in: range) { value, part, stop in
            guard value != nil else { return }
            result = text.attributes(at: part.location, effectiveRange: nil)
            stop.pointee = true
        }
        return result
    }
    /// The hidden rule characters within `range`.
    static func markerRanges(_ text: NSAttributedString, in range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        text.enumerateAttribute(.journalMarker, in: range) { value, part, _ in
            if value != nil { result.append(part) }
        }
        return result
    }
    /// The text in `range` without its hidden markers.
    static func content(_ text: NSAttributedString, in range: NSRange) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        for marker in markerRanges(text, in: range).reversed() {
            result.deleteCharacters(in: NSRange(location: marker.location - range.location, length: marker.length))
        }
        return result
    }
}
extension PlatformColor {
    static var labelColorCompat: PlatformColor {
        #if os(macOS)
            .labelColor
        #else
            .label
        #endif
    }
}

#if os(iOS)
    /// Text views that show the Format panel in place of the keyboard, where Escape closes it.
    @MainActor @objc protocol FormattingPanelClosing {
        func closeFormattingPanel()
    }

    extension EditorActions {
        /// Escape on a hardware keyboard while the Format panel or popover is shown.
        func formattingEscapeCommand() -> UIKeyCommand? {
            guard formatting.isPresented else { return nil }
            let command = UIKeyCommand(
                input: UIKeyCommand.inputEscape, modifierFlags: [],
                action: #selector(FormattingPanelClosing.closeFormattingPanel))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }
#endif
