import SwiftUI
import UniformTypeIdentifiers

struct LockView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Dartiqo")
                    .font(.largeTitle.bold())
                Label("Profil je zamčený", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Odemknout profil") { Task { await store.authenticate() } }
                .buttonStyle(PrimaryButton())
            if let error = store.authError {
                Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.authenticate()
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
