import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers

struct LockView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    /// Dokud je přes zámek úvodní obrazovka, biometrie počká, ať je zámek vidět.
    var promptsAutomatically = true
    private let biometry = BiometryKind.current

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            lockMark
            VStack(spacing: 8) {
                Text("Dartiqo")
                    .font(AppFont.display(34))
                Text("Aplikace je zamčená")
                    .font(AppFont.body())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: biometry.symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)
                .padding(.top, 4)
            Spacer()
            Button(biometry.unlockTitle) { Task { await store.authenticate() } }
                .buttonStyle(PrimaryButton())
            if let error = store.authError {
                Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .task(id: promptsAutomatically) {
            guard promptsAutomatically, scenePhase == .active else { return }
            await store.authenticate()
        }
        .onChange(of: scenePhase) { _, phase in
            guard promptsAutomatically, phase == .active else { return }
            Task { await store.authenticate() }
        }
    }

    private var lockMark: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Zakryje hru v přepínači aplikací. Biometrii nespouští — ta přijde až po návratu, když uběhne doba.
struct PrivacyCover: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(Theme.brand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

private enum BiometryKind {
    case faceID, touchID, opticID, deviceCode

    static var current: BiometryKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .deviceCode }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .deviceCode
        @unknown default: return .deviceCode
        }
    }

    var symbol: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .deviceCode: return "lock.fill"
        }
    }

    var unlockTitle: String {
        switch self {
        case .faceID: return "Odemknout přes Face ID"
        case .touchID: return "Odemknout přes Touch ID"
        case .opticID: return "Odemknout přes Optic ID"
        case .deviceCode: return "Odemknout kódem zařízení"
        }
    }
}

struct StorageRecoveryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var document: JSONDocument?
    @State private var exporting = false
    @State private var reset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.positive)
                .accessibilityHidden(true)
            Text("Tvoje data potřebují pozornost.")
                .font(.largeTitle.bold())
            Text("Uložené hry se nepodařilo načíst. Původní data jsme ponechali beze změny. Ulož jejich kopii pro obnovu, nebo začni znovu s prázdným profilem.")
                .foregroundStyle(.secondary)
            Button("Uložit kopii původních dat") {
                do { document = try store.recoveryDocument(); exporting = true }
                catch { store.storageError = error.localizedDescription }
            }
            .buttonStyle(PrimaryButton())
            Button("Začít znovu", role: .destructive) { reset = true }
        }
        .padding(28)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Dartiqo-recovery") { result in
            if case .failure(let error) = result { store.storageError = error.localizedDescription }
        }
        .confirmationDialog("Vytvořit prázdná data?", isPresented: $reset, titleVisibility: .visible) {
            Button("Začít znovu", role: .destructive) { store.resetAfterRecovery() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Původní soubor se ponechá jako interní záloha. Před pokračováním doporučujeme uložit také vlastní kopii.")
        }
    }
}

#if DEBUG
#Preview("Zámek") {
    LockView().dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#Preview("Obnova") {
    StorageRecoveryView().dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
