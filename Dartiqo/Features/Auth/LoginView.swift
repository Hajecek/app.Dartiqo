import AuthenticationServices
import SwiftUI

/// Přihlášení k webovému účtu Dartiqo. Bez účtu se do aplikace nevstoupí.
struct LoginView: View {
    @ObservedObject private var account = DartiqoAccount.shared
    @State private var identity = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var server = ""
    @State private var showServer = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case identity, password, server }

    private var canLogin: Bool {
        !busy && !identity.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brand
                    Spacer(minLength: 40)
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                        form
                        socialButtons
                        footer
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { background }
        .environment(\.colorScheme, .dark)
        .onAppear { server = account.serverURL }
    }

    // MARK: - Části obrazovky

    private var background: some View {
        ZStack(alignment: .top) {
            Color.black
            Image("LoginBackground")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.45), .init(color: .clear, location: 0.85)], startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var brand: some View {
        HStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Theme.brand.opacity(0.35), radius: 16)
            Text("Dartiqo")
                .font(AppFont.title(24, weight: .heavy))
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hra začíná\nu tebe.")
                .font(AppFont.display(40, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Přihlas se stejným účtem jako na webu a rozehraný zápas uvidíš živě i na počítači.")
                .font(AppFont.body(16))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var form: some View {
        VStack(spacing: 12) {
            AuthField(icon: "person.fill", focused: focus == .identity) {
                TextField("E-mail nebo uživatelské jméno", text: $identity)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .focused($focus, equals: .identity)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            AuthField(icon: "lock.fill", focused: focus == .password) {
                Group {
                    if showPassword {
                        TextField("Heslo", text: $password)
                    } else {
                        SecureField("Heslo", text: $password)
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
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(showPassword ? "Skrýt heslo" : "Zobrazit heslo")
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            Button {
                focus = nil
                Task { await login() }
            } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView().tint(.black) }
                    Text(busy ? "Přihlašuji…" : "Přihlásit se")
                }
            }
            .buttonStyle(PrimaryButton())
            .disabled(!canLogin)
            .opacity(canLogin || busy ? 1 : 0.5)
            .shadow(color: Theme.brand.opacity(canLogin ? 0.3 : 0), radius: 18, y: 6)
        }
        .animation(.snappy, value: error)
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                Text("nebo")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            }
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await appleCompleted(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(busy)
            Button {
                error = "Přihlášení přes Google připravujeme. Zatím použij e-mail a heslo."
            } label: {
                HStack(spacing: 10) {
                    GoogleMark().frame(width: 18, height: 18)
                    Text("Pokračovat přes Google")
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if let register = URL(string: account.serverURL + "/register") {
                Link(destination: register) {
                    (Text("Nemáš účet? ").foregroundStyle(.white.opacity(0.55)) + Text("Zaregistruj se na webu").foregroundStyle(Theme.brand).bold())
                        .font(.footnote)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { showServer.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                        Text(server.isEmpty ? account.serverURL : server)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showServer ? 180 : 0))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adresa serveru")
                if showServer {
                    AuthField(icon: "server.rack", focused: focus == .server) {
                        TextField("Adresa serveru", text: $server)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focus, equals: .server)
                    }
                    Text("Simulátor: http://localhost/dartiqo. iPhone ve stejné Wi-Fi jako Mac s XAMPPem: IP adresa Macu, třeba http://192.168.1.20/dartiqo.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
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

/// Pole na tmavém skle s ikonou. Zvýrazní se, když je aktivní.
private struct AuthField<Content: View>: View {
    var icon: String
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(focused ? Theme.brand : .white.opacity(0.45))
                .frame(width: 20)
            content
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? Theme.brand.opacity(0.8) : .white.opacity(0.12), lineWidth: 1)
        )
        .animation(.snappy, value: focused)
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
