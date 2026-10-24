import AuthenticationServices
import SwiftUI

/// Přihlášení k webovému účtu Dartiqo. Bez účtu se do aplikace nevstoupí.
struct LoginView: View {
    @ObservedObject private var account = DartiqoAccount.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var identity = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var server = ""
    @State private var showServer = false
    @State private var busy = false
    @State private var error: String?
    @State private var appeared = false
    @State private var boardAngle = 0.0
    @FocusState private var focus: Field?

    private enum Field { case identity, password }

    /// Stejná žlutá jako pozadí loga, aby logo na plakátu splynulo.
    private let poster = Color("LaunchBackground")

    private var canLogin: Bool {
        !busy && !identity.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    /// Při psaní se plakát smrskne, aby formulář zůstal nad klávesnicí.
    private var compact: Bool { focus != nil }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    hero(minHeight: compact ? 0 : max(300, geo.size.height * 0.46))
                    Spacer(minLength: 0)
                    panel
                        .offset(y: appeared || reduceMotion ? 0 : 80)
                        .opacity(appeared ? 1 : 0)
                }
                .frame(minHeight: geo.size.height)
                .background(poster)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            VStack(spacing: 0) { poster; Color.black }
                .ignoresSafeArea()
        }
        .animation(.snappy(duration: 0.35), value: compact)
        .sheet(isPresented: $showServer) {
            ServerSheet(server: $server, defaultServer: account.serverURL)
        }
        .onAppear {
            if server.isEmpty { server = account.serverURL }
            withAnimation(.spring(duration: 0.7, bounce: 0.25).delay(0.05)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) { boardAngle = 360 }
        }
    }

    // MARK: - Plakát

    private func hero(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            if !compact {
                Spacer(minLength: 28)
                headline
                    .offset(y: appeared || reduceMotion ? 0 : 24)
                    .opacity(appeared ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, compact ? 20 : 40)
        .frame(maxWidth: 560, minHeight: minHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(alignment: .topTrailing) {
            BoardLines(color: .black.opacity(0.11))
                .frame(width: 440, height: 440)
                .rotationEffect(.degrees(boardAngle))
                .offset(x: 170, y: compact ? -260 : -30)
                .opacity(compact ? 0 : 1)
        }
        .clipped()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text("Dartiqo")
                .font(AppFont.title(22, weight: .black))
                .foregroundStyle(.black)
                .padding(.leading, -8)
            Spacer()
            Button { showServer = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(poster)
                    .frame(width: 40, height: 40)
                    .background(.black, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nastavení serveru")
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Každá\nšipka\nse počítá.")
                .font(AppFont.display(56, weight: .black))
                .foregroundStyle(.black)
                .lineSpacing(-6)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text("Statistiky, přátelé a živé zápasy.\nJeden účet pro aplikaci i web.")
                .font(AppFont.body(15, weight: .semibold))
                .foregroundStyle(.black.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Panel s formulářem

    private var panel: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Přihlášení")
                    .font(AppFont.title(30, weight: .black))
                Text("Vítej zpátky u terče.")
                    .font(AppFont.body(15))
                    .foregroundStyle(.white.opacity(0.5))
            }
            form
            divider
            socialButtons
            footer
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            LineField(title: "E-mail nebo přezdívka", focused: focus == .identity, accent: poster) {
                TextField("", text: $identity, prompt: Text("jmeno@email.cz").foregroundStyle(.white.opacity(0.25)))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .focused($focus, equals: .identity)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            .onTapGesture { focus = .identity }

            LineField(title: "Heslo", focused: focus == .password, accent: poster) {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: Text("••••••••").foregroundStyle(.white.opacity(0.25)))
                        } else {
                            SecureField("", text: $password, prompt: Text("••••••••").foregroundStyle(.white.opacity(0.25)))
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canLogin { Task { await login() } } }
                    Button { showPassword.toggle() } label: {
                        Text(showPassword ? "Skrýt" : "Ukázat")
                            .font(AppFont.caption(13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Skrýt heslo" : "Zobrazit heslo")
                }
            }
            .onTapGesture { focus = .password }

            if let error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.47))
                .padding(14)
                .background(Color(red: 1, green: 0.3, blue: 0.25).opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            loginButton
                .padding(.top, 4)
        }
        .animation(.snappy, value: error)
    }

    private var loginButton: some View {
        Button {
            focus = nil
            Task { await login() }
        } label: {
            HStack {
                Text(busy ? "Přihlašuji…" : "Přihlásit se")
                    .font(AppFont.body(18, weight: .bold))
                Spacer()
                ZStack {
                    Circle().fill(.black)
                    if busy {
                        ProgressView().tint(poster)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(poster)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .foregroundStyle(.black)
            .padding(.leading, 24)
            .padding(.trailing, 6)
            .frame(height: 56)
            .background(poster, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .disabled(!canLogin)
        .opacity(canLogin || busy ? 1 : 0.4)
        .animation(.snappy, value: canLogin)
    }

    private var divider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            Text("NEBO")
                .font(AppFont.caption(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize()
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await appleCompleted(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(Capsule())
            .disabled(busy)

            Button {
                error = "Přihlášení přes Google připravujeme. Zatím použij e-mail a heslo."
            } label: {
                HStack(spacing: 10) {
                    GoogleMark().frame(width: 18, height: 18)
                    Text("Pokračovat přes Google")
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScale())
            .disabled(busy)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let register = URL(string: account.serverURL + "/register") {
            Link(destination: register) {
                HStack(spacing: 4) {
                    Text("Nemáš účet?").foregroundStyle(.white.opacity(0.5))
                    Text("Zaregistruj se").foregroundStyle(poster).bold()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(poster)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
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

/// Pole bez rámečku: popisek, hodnota a čára, která se při psaní vyplní akcentem.
private struct LineField<Content: View>: View {
    var title: String
    var focused: Bool
    var accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(AppFont.caption(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(focused ? accent : .white.opacity(0.45))
            content
                .font(AppFont.body(19, weight: .medium))
                .foregroundStyle(.white)
                .tint(accent)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                Rectangle().fill(accent).frame(height: 2)
                    .scaleEffect(x: focused ? 1 : 0, anchor: .leading)
            }
        }
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.3), value: focused)
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
            VStack(alignment: .leading, spacing: 18) {
                LineField(title: "Adresa serveru", focused: focused, accent: Theme.brand) {
                    TextField("", text: $server, prompt: Text(defaultServer).foregroundStyle(.white.opacity(0.25)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { dismiss() }
                }
                .onTapGesture { focused = true }
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
            .padding(24)
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
        .presentationBackground(Color(white: 0.06))
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
