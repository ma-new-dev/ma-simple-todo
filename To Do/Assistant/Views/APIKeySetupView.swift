import SwiftUI

struct APIKeySetupView: View {
    let onSave: (String) -> Void

    @State private var key = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Connect Claude")
                    .font(.title2.bold())
                Text("Enter your Anthropic API key to enable the AI assistant.\nGet one at console.anthropic.com")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SecureField("sk-ant-api03-...", text: $key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            Button {
                let trimmed = key.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onSave(trimmed)
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
