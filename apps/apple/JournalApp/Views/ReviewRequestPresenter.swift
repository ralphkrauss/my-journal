import StoreKit
import SwiftUI

/// Gives the rating request the window's own `requestReview`, so the system shows its prompt over this window
/// (docs/design/about-and-ratings-2026-10-05.md §3).
struct ReviewRequestPresenter: ViewModifier {
    let model: AppModel
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.onAppear {
            let request = requestReview
            model.reviewRequests.present = { request() }
        }
    }
}
