import SwiftUI

@main struct DartiqoApp: App {
    @StateObject private var store = AppStore()
    @ObservedObject private var account = DartiqoAccount.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .scrollIndicators(.hidden)
                .tint(Theme.action)
                .preferredColorScheme(store.data.appearance == "system" ? nil : store.data.appearance == "dark" ? .dark : .light)
                .task { await account.refresh() }
                // $data hlásí novou hodnotu ještě před zápisem, proto se zápas čte z ní, ne ze store
                .onReceive(store.$data) { data in
                    account.syncLive(data.selectedProfile.flatMap { data.activeMatches[$0.uuidString] })
                }
                .onChange(of: account.user) { _, _ in account.syncLive(store.activeMatch) }
                .onChange(of: account.liveSharing) { _, _ in account.syncLive(store.activeMatch) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { account.syncLive(store.activeMatch) }
                    if phase == .background {
                        store.flushSave()
                        if store.data.biometricLock && store.profile != nil { store.locked = true }
                    }
                }
                .alert("Ukládání", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                    Button("Rozumím") { store.storageError = nil }
                } message: { Text(store.storageError ?? "") }
        }
    }
}
