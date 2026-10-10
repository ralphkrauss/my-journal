import SwiftUI

/// Settings ▸ Privacy ▸ Encryption: every library is encrypted, so this tells so and offers Change Password.
struct EncryptionSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            Text("Your Journals Are Encrypted")
            ChangePasswordButton()
        } header: {
            Text("Encryption")
        } footer: {
            Text(
                "Keep your \(model.configuration?.credentialName.lowercased() ?? "password") somewhere safe. It can’t be recovered."
            )
        }
    }
}
