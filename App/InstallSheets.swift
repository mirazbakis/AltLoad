import SwiftUI

// MARK: - Apple ID

struct SignInSheet: View {
    let anisetteURL: String
    let onContinue: (AppleIDCredentials, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = AppleIDStore.email
    @State private var password = ""
    @State private var remember = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apple ID email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Your password goes only to Apple. Apple also requires device-identity headers (\"anisette\"), which AltLoad gets from \(host). You can use a secondary Apple ID if you prefer.")
                }
                .auroraRow()

                Section {
                    Toggle("Remember password", isOn: $remember)
                } footer: {
                    Text("Kept in this iPhone's Keychain so refreshing is one tap. It never syncs to iCloud.")
                }
                .auroraRow()
            }
            .auroraListBackground()
            .navigationTitle("Apple ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onContinue(AppleIDCredentials(email: email.trimmingCharacters(in: .whitespaces), password: password), remember)
                        dismiss()
                    }
                    .disabled(email.isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                if password.isEmpty, !email.isEmpty, let saved = AppleIDStore.password(for: email) {
                    password = saved
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var host: String {
        URL(string: anisetteURL)?.host() ?? anisetteURL
    }
}

// MARK: - Two-factor

struct TwoFactorSheet: View {
    let prompt: TwoFactorPrompt
    let respond: (String) -> Void
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .onChange(of: code) { _, value in
                            code = String(value.filter(\.isNumber).prefix(6))
                        }
                } header: {
                    Text(headline)
                } footer: {
                    if let error = prompt.lastError, !error.isEmpty {
                        Text(error).foregroundStyle(Aurora.danger)
                    }
                }
                .auroraRow()

                Section("Other options") {
                    Button("Send code to my Apple devices") { respond("devices") }
                    ForEach(prompt.numbers.filter { $0.id != prompt.selectedNumberID || !prompt.sms }) { number in
                        Button("Text \(number.number)") { respond("sms:\(number.id)") }
                    }
                    if !prompt.unknown {
                        Button("Resend code") { respond("resend") }
                    }
                }
                .auroraRow()
            }
            .auroraListBackground()
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { respond("abort") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify") { respond("code:\(code)") }
                        .disabled(code.count != 6)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var headline: String {
        if prompt.unknown { return "Choose where to get your code" }
        if prompt.sms,
           let id = prompt.selectedNumberID,
           let number = prompt.numbers.first(where: { $0.id == id }) {
            return "Enter the code sent to \(number.number)"
        }
        return "Enter the code shown on your other Apple devices"
    }
}

// MARK: - Certificate limit

struct RevokeSheet: View {
    let prompt: RevokePrompt
    let respond: (String) -> Void
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(prompt.certificates) { cert in
                        Button {
                            if selected.contains(cert.serial) {
                                selected.remove(cert.serial)
                            } else {
                                selected.insert(cert.serial)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cert.machine.isEmpty ? "Unknown machine" : cert.machine)
                                        .font(.headline)
                                    Text(cert.name.isEmpty ? cert.serial : cert.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(cert.serial) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Aurora.violet)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Your Apple ID has reached its limit of development certificates. Choose one to revoke. Apps signed with it by another computer or tool will stop opening until they're signed again.")
                }
                .auroraRow()
            }
            .auroraListBackground()
            .navigationTitle("Certificate Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { respond("abort") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Revoke", role: .destructive) {
                        let data = (try? JSONEncoder().encode(Array(selected))) ?? Data("[]".utf8)
                        respond(String(data: data, encoding: .utf8) ?? "[]")
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
