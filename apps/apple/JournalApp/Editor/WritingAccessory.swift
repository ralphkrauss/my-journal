#if os(iOS)
    import SwiftUI
    import UIKit

    /// The writing controls while typing: above the on-screen keyboard, or at the bottom of the screen with a
    /// hardware keyboard. The bottom bar hides meanwhile, so one set of controls shows at a time.
    @MainActor final class WritingAccessory: UIInputView {
        private let host: UIHostingController<WritingAccessoryBar>
        private let capsule: AnchorBox
        init(actions: EditorActions) {
            let capsule = AnchorBox()
            self.capsule = capsule
            host = UIHostingController(rootView: WritingAccessoryBar(actions: actions, capsule: capsule))
            super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 56), inputViewStyle: .default)
            allowsSelfSizing = true
            backgroundColor = .clear
            host.view.backgroundColor = .clear
            host.sizingOptions = .intrinsicContentSize
            host.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.view.topAnchor.constraint(equalTo: topAnchor),
                host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { nil }

        /// The accessory spans the keyboard's width, but only the controls' capsule takes touches: beside it, they
        /// reach the entries list and sidebar, as in Notes.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let view = capsule.view, view.window != nil, view.window === window else {
                return super.point(inside: point, with: event)
            }
            return view.convert(view.bounds, to: self).contains(point)
        }

        /// Where the controls' capsule is drawn, while it's shown.
        func capsuleFrame(in space: UICoordinateSpace) -> CGRect? {
            guard let view = capsule.view, view.window != nil, !isHidden else { return nil }
            return view.convert(view.bounds, to: space)
        }

        /// The iPad keyboard's shortcut bar offers the system's own B, I, U and text format controls beside ours; as
        /// in Notes, only the entry's Formatting shows. Undo, redo and paste stay.
        static func hideSystemFormatting(of view: UITextView) {
            view.inputAssistantItem.trailingBarButtonGroups = []
        }
    }

    /// The same controls, order and look as the editor's bottom bar.
    struct WritingAccessoryBar: View {
        @ObservedObject var actions: EditorActions
        let capsule: AnchorBox
        @Environment(\.horizontalSizeClass) private var sizeClass
        @State private var anchor = AnchorBox()

        var body: some View {
            ReadingBar(fitsContents: sizeClass == .regular, capsule: capsule) {
                FormattingButton(session: actions.formatting) {
                    actions.toggleFormatting?(anchor.view)
                }
                .background(AnchorView(box: anchor))
                InsertImageMenu(editor: actions)
                if sizeClass != .regular { Spacer(minLength: 16) }
                Button {
                    actions.toggleSourceMode()
                } label: {
                    Label(
                        actions.sourceMode ? "View Preview" : "View Source",
                        systemImage: actions.sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }

    /// Insert Image on iPhone and iPad: the photo library first, as in Notes, then the camera and Files.
    struct InsertImageMenu: View {
        let editor: EditorActions
        var body: some View {
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { editor.insertImage(from: .photos) }
                if CameraPicker.isAvailable {
                    Button("Take Photo", systemImage: "camera") { editor.insertImage(from: .camera) }
                }
                Button("Choose File…", systemImage: "folder") { editor.insertImage(from: .files) }
            } label: {
                Label("Insert Image", systemImage: "photo")
            }
        }
    }

    /// Holds a control's view, so the regular-width popover can point at it or touches can be limited to it.
    @MainActor final class AnchorBox {
        weak var view: UIView?
    }

    struct AnchorView: UIViewRepresentable {
        let box: AnchorBox
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            box.view = view
            return view
        }
        func updateUIView(_ view: UIView, context: Context) { box.view = view }
    }
#endif
