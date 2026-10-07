import SwiftUI

@main struct DartiqoApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.action)
                .preferredColorScheme(store.data.appearance == "system" ? nil : store.data.appearance == "dark" ? .dark : .light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        store.save()
                        if store.data.biometricLock && store.profile != nil { store.locked = true }
                    }
                }
                .alert("Ukládání", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
                    Button("Rozumím") { store.storageError = nil }
                } message: { Text(store.storageError ?? "") }
        }
    }
}
