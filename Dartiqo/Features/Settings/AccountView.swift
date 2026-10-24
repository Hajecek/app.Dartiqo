import SwiftUI

/// Přihlášený webový účet Dartiqo a živý přenos zápasu na web.
struct AccountView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @State private var confirmLogout = false

    var body: some View {
        Form {
            if let user = account.user {
                Section {
                    LabeledContent("Jméno", value: user.fullName)
                    LabeledContent("Uživatel", value: "@\(user.username)")
                    LabeledContent("E-mail", value: user.email)
                    LabeledContent("Server", value: account.serverURL)
                } header: {
                    Text("Přihlášený účet")
                }
            }
            if account.isGuest {
                Section {
                    Button("Přihlásit se k účtu") { store.signOut(); account.leaveGuest() }
                } header: {
                    Text("Hraješ bez účtu")
                } footer: {
                    Text("Hry a statistiky zůstávají jen v tomto telefonu. S účtem je uvidíš i na webu, můžeš hrát s přáteli a sledovat zápas živě na počítači. Hry hosta se k účtu nepřenesou.")
                }
            } else {
                Section {
                    Toggle("Živý přenos na web", isOn: $account.liveSharing).tint(Theme.mint)
                } footer: {
                    Text("Rozehraný zápas se po každé šipce ukáže na webu. V Přehledu vyskočí banner Živě z mobilu a zápas pak sleduješ na celé obrazovce počítače.")
                }
                Section {
                    Button("Odhlásit se", role: .destructive) { confirmLogout = true }
                }
            }
        }
        .navigationTitle("Dartiqo účet")
        .navigationBarTitleDisplayMode(.inline)
        .logoutConfirmation(isPresented: $confirmLogout)
    }
}

extension View {
    /// Potvrzení odhlášení. Hry zůstanou v telefonu u profilu účtu a po dalším přihlášení se vrátí.
    func logoutConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(LogoutConfirmation(isPresented: isPresented))
    }
}

private struct LogoutConfirmation: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog("Odhlásit se z účtu Dartiqo?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Odhlásit se", role: .destructive) {
                store.signOut()
                Task { await DartiqoAccount.shared.logout() }
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Hry zůstanou v telefonu a po dalším přihlášení se vrátí.")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { AccountView() }.dartiqoPreview()
}
#endif
