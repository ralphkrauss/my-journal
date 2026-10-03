import SwiftUI

/// Shown above the writing while chosen images are read, once that takes more than a moment, with Stop
/// (docs/design/several-photos-2026-10-03.md). Laid out like the conflict notice.
struct ImageImportNotice: View {
    @ObservedObject var session: ImageInsertionSession
    let stop: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let progress = session.progress {
                notice(progress)
                    .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .default, value: session.progress == nil)
    }

    private func notice(_ progress: (done: Int, total: Int)) -> some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
        let single = progress.total == 1
        return layout {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text(single ? "Adding Image…" : "Adding Images… \(progress.done) of \(progress.total)")
                    .font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(single ? "Adding Image" : "Adding Images")
            .accessibilityValue(single ? "" : "\(progress.done) of \(progress.total)")
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Button("Stop", action: stop)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, ignoresSafeAreaEdges: [])
    }
}
