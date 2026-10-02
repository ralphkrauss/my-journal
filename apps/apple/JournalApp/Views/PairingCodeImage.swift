import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code a new device scans to connect. Drawn black on white with a quiet margin, so it scans in Dark Mode, at
/// a fixed size that doesn't grow with Dynamic Type.
struct PairingCodeImage: View {
    let text: String
    var size: CGFloat = 220
    var body: some View {
        Group {
            if let image = Self.render(text) {
                Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size).padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement().accessibilityLabel("Code for adding a new device").accessibilityAddTraits(.isImage)
    }

    private static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
