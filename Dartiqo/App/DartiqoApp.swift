import SwiftUI

@main struct DartiqoApp: App {
    @UIApplicationDelegateAdaptor(PushRegistrar.self) private var pushRegistrar
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
                .task {
                    await account.refresh(into: store)
                    account.startWatching(store: store)
                    if account.isSignedIn { await pushRegistrar.registerForPushes() }
                }
                .onChange(of: account.user?.id) { _, _ in
                    guard account.isSignedIn else { return }
                    Task {
                        await pushRegistrar.registerForPushes()
                        if let token = pushRegistrar.currentToken() {
                            await account.uploadPushToken(token)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .dartiqoPushToken)) { note in
                    guard let token = note.object as? String else { return }
                    Task { await account.uploadPushToken(token) }
                }
                // $data hlásí novou hodnotu ještě před zápisem, proto se zápas čte z ní, ne ze store
                .onReceive(store.$data) { data in
                    account.syncLive(data.selectedProfile.flatMap { data.activeMatches[$0.uuidString] })
                }
                .onChange(of: account.user) { _, _ in account.syncLive(store.activeMatch) }
                // Ne .task(id:): zrušení by přerušilo rozběhnuté odesílání
                .onChange(of: "\(account.user?.id ?? 0)|\(store.matchSyncKey)", initial: true) { _, _ in
                    Task { await account.syncMatches(store) }
                }
                .onChange(of: account.liveSharing) { _, _ in account.syncLive(store.activeMatch) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        account.syncLive(store.activeMatch)
                        account.startWatching(store: store)
                        store.noteReturned()
                        Task {
                            await account.refresh(into: store)
                            await account.syncMatches(store)
                        }
                    }
                    if phase == .background {
                        account.stopWatching()
                        store.noteLeftForeground()
                        store.flushSave()
                    }
                }
                .alert("Ukládání", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                    Button("Rozumím") { store.storageError = nil }
                } message: { Text(store.storageError ?? "") }
        }
    }
}
