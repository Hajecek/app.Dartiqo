import SwiftUI

/// Přihlášení k webovému účtu Dartiqo kvůli živému přenosu zápasu na web.
struct AccountView: View {
    @ObservedObject private var account = DartiqoAccount.shared
    @State private var identity = ""
    @State private var password = ""
    @State private var server = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            if let user = account.user {
                Section {
                    LabeledContent("Jméno", value: user.fullName)
                    LabeledContent("Uživatel", value: "@\(user.username)")
                    LabeledContent("Server", value: account.serverURL)
                } header: {
                    Text("Přihlášený účet")
                }
                Section {
                    Toggle("Živý přenos na web", isOn: $account.liveSharing).tint(Theme.mint)
                } footer: {
                    Text("Rozehraný zápas se po každé šipce ukáže na webu. V Přehledu vyskočí banner Živě z mobilu a zápas pak sleduješ na celé obrazovce počítače.")
                }
                Section {
                    Button("Odhlásit", role: .destructive) {
                        Task { await account.logout() }
                    }
                }
            } else {
                Section {
                    TextField("E-mail nebo uživatelské jméno", text: $identity)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("Heslo", text: $password)
                        .textContentType(.password)
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            Text("Přihlásit")
                            if busy {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(busy || identity.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Přihlášení")
                } footer: {
                    Text("Použij stejný účet jako na webu Dartiqo.")
                }
                Section {
                    TextField("Adresa serveru", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Simulátor: http://localhost/dartiqo. iPhone ve stejné Wi-Fi jako Mac s XAMPPem: IP adresa Macu, třeba http://192.168.1.20/dartiqo. Ostrý provoz: https adresa webu.")
                }
            }
        }
        .navigationTitle("Dartiqo účet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { server = account.serverURL }
    }

    private func login() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await account.login(server: server, identity: identity.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { AccountView() }.dartiqoPreview()
}
#endif
