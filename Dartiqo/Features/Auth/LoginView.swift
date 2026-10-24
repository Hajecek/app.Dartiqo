import AuthenticationServices
import SwiftUI

/// Přihlášení k webovému účtu Dartiqo, nebo vstup bez účtu na místní profil.
struct LoginView: View {
    @ObservedObject private var account = DartiqoAccount.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var identity = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var server = ""
    @State private var showServer = false
    @State private var confirmGuest = false
    @State private var busy = false
    @State private var error: String?
    @State private var appeared = false
    @FocusState private var focus: Field?

    private enum Field { case identity, password }

    private var canLogin: Bool {
        !busy && !identity.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 12)
                    header
                        .reveal(appeared, delay: 0, reduceMotion: reduceMotion)
                    Spacer(minLength: 28)
                    VStack(spacing: 14) {
                        socialButtons
                        divider
                        form
                    }
                    .reveal(appeared, delay: 0.1, reduceMotion: reduceMotion)
                    Spacer(minLength: 28)
                    footer
                        .reveal(appeared, delay: 0.2, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { background }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showServer) {
            ServerSheet(server: $server, defaultServer: account.serverURL)
        }
        .confirmationDialog("Pokračovat bez přihlášení?", isPresented: $confirmGuest, titleVisibility: .visible) {
            Button("Hrát bez účtu") { account.continueAsGuest() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Hry a statistiky zůstanou jen v tomto telefonu. Přátelé, web a živý přenos fungují jen s účtem. Přihlásit se můžeš kdykoli v Nastavení.")
        }
        .onAppear {
            if server.isEmpty { server = account.serverURL }
            appeared = true
        }
    }

    // MARK: - Části obrazovky

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.brand.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.08), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showServer = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nastavení serveru")
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: Theme.brand.opacity(0.35), radius: 24, y: 6)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Vítej v Dartiqo")
                    .font(AppFont.display(32, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Přihlas se a měj statistiky, přátele\na živé zápasy na mobilu i na webu.")
                    .font(AppFont.body(16))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var socialButtons: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await appleCompleted(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(busy)

            Button {
                focus = nil
                error = "Přihlášení přes Google připravujeme. Zatím použij Apple nebo e-mail."
            } label: {
                HStack(spacing: 10) {
                    GoogleMark().frame(width: 19, height: 19)
                    Text("Pokračovat přes Google")
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScale())
            .disabled(busy)
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            Text("nebo e-mailem")
                .font(AppFont.caption(13))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize()
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var form: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                FieldRow(icon: "envelope", focused: focus == .identity) {
                    TextField("", text: $identity, prompt: Text("E-mail nebo přezdívka").foregroundStyle(.white.opacity(0.35)))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($focus, equals: .identity)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.leading, 50)
                FieldRow(icon: "lock", focused: focus == .password) {
                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: Text("Heslo").foregroundStyle(.white.opacity(0.35)))
                        } else {
                            SecureField("", text: $password, prompt: Text("Heslo").foregroundStyle(.white.opacity(0.35)))
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canLogin { Task { await login() } } }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Skrýt heslo" : "Zobrazit heslo")
                }
            }
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focus != nil ? Theme.brand.opacity(0.7) : .white.opacity(0.08), lineWidth: 1)
            )
            .animation(.snappy(duration: 0.2), value: focus)

            if let error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.52))
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                focus = nil
                Task { await login() }
            } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView().tint(.black) }
                    Text(busy ? "Přihlašuji…" : "Přihlásit se")
                        .font(AppFont.body(18, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScale())
            .disabled(!canLogin)
            .opacity(canLogin || busy ? 1 : 0.35)
            .animation(.snappy, value: canLogin)
        }
        .animation(.snappy, value: error)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Button {
                focus = nil
                confirmGuest = true
            } label: {
                HStack(spacing: 6) {
                    Text("Pokračovat bez přihlášení")
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .font(AppFont.body(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScale())
            .disabled(busy)

            if let register = URL(string: account.serverURL + "/register") {
                Link(destination: register) {
                    HStack(spacing: 4) {
                        Text("Nemáš účet?").foregroundStyle(.white.opacity(0.5))
                        Text("Zaregistruj se").foregroundStyle(Theme.brand).bold()
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Akce

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

    private func appleCompleted(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                error = "Apple nevrátil přihlašovací token."
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? ""
            busy = true
            error = nil
            defer { busy = false }
            do {
                try await account.login(server: server, provider: .apple, idToken: idToken, name: name)
            } catch {
                self.error = error.localizedDescription
            }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = "Přihlášení přes Apple se nepodařilo. \(failure.localizedDescription)"
        }
    }
}

private extension View {
    /// Postupné odhalení po otevření obrazovky. Se sníženým pohybem jen prolnutí.
    func reveal(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 20)
            .animation(.spring(duration: 0.6, bounce: 0.15).delay(delay), value: shown)
    }
}

/// Řádek ve společném bloku polí. Ikona se zbarví, když je pole aktivní.
private struct FieldRow<Content: View>: View {
    var icon: String
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(focused ? Theme.brand : .white.opacity(0.4))
                .frame(width: 22)
            content
                .font(AppFont.body(17))
                .foregroundStyle(.white)
                .tint(Theme.brand)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 56)
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Adresa serveru. Výchozí hodnotu bere z účtu, upravená platí pro další přihlášení.
private struct ServerSheet: View {
    @Binding var server: String
    var defaultServer: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                FieldRow(icon: "server.rack", focused: focused) {
                    TextField("", text: $server, prompt: Text(defaultServer).foregroundStyle(.white.opacity(0.35)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { dismiss() }
                }
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(focused ? Theme.brand.opacity(0.7) : .white.opacity(0.08), lineWidth: 1)
                )
                Label {
                    Text("Simulátor: http://localhost/dartiqo. iPhone ve stejné Wi-Fi jako Mac s XAMPPem: IP adresa Macu, třeba http://192.168.1.20/dartiqo.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                if server != defaultServer {
                    Button("Obnovit výchozí") { server = defaultServer }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                        .tint(Theme.brand)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(white: 0.07))
        .environment(\.colorScheme, .dark)
    }
}

/// Barevné „G“ podle Google brand guidelines, kreslené bez externího assetu.
private struct GoogleMark: View {
    private let segments: [(Color, CGFloat, CGFloat)] = [
        (Color(red: 0.26, green: 0.52, blue: 0.96), 0.0, 0.13),
        (Color(red: 0.20, green: 0.66, blue: 0.33), 0.13, 0.38),
        (Color(red: 0.98, green: 0.74, blue: 0.02), 0.38, 0.6),
        (Color(red: 0.92, green: 0.26, blue: 0.21), 0.6, 0.875)
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.22
            ZStack {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    Circle()
                        .trim(from: segment.1, to: segment.2)
                        .stroke(segment.0, style: StrokeStyle(lineWidth: line))
                }
                Rectangle()
                    .fill(segments[0].0)
                    .frame(width: size / 2, height: line)
                    .offset(x: size / 4)
            }
            .padding(line / 2)
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    LoginView().dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
