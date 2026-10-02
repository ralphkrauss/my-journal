#if os(iOS)
    import SwiftUI

    /// A single inset owns reading controls; the keyboard owns its separate native input accessory.
    struct ReadingBar<Content: View>: View {
        var fitsContents = false
        /// Records the capsule's view, for a keyboard accessory that takes touches only there.
        var capsule: AnchorBox?
        @ViewBuilder var content: Content
        var body: some View {
            surface.background { if let capsule { AnchorView(box: capsule) } }
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
        @ViewBuilder private var surface: some View {
            if #available(iOS 26.0, *) {
                controls.glassEffect(.regular, in: Capsule())
            } else {
                controls.background(.bar, in: Capsule())
            }
        }
        private var controls: some View {
            ViewThatFits(in: .horizontal) {
                row
                ScrollView(.horizontal) { row }.scrollIndicators(.visible)
                    .accessibilityIdentifier("Reading Controls")
            }
            .frame(maxWidth: fitsContents ? nil : 600).fixedSize(horizontal: false, vertical: true)
            .labelStyle(.iconOnly).buttonStyle(ReadingButtonStyle()).tint(.primary)
        }
        private var row: some View {
            HStack(spacing: 8) { content }.padding(.horizontal, 8).padding(.vertical, 2)
        }
    }
    private struct ReadingButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.font(.title3).frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
        }
    }
#endif
