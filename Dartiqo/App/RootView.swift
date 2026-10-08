import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.needsRecovery { StorageRecoveryView() }
            else if store.locked { LockView() }
            else if store.profile == nil { WelcomeView() }
            else { MainTabView() }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Domů", systemImage: "house.fill") }
            NavigationStack { PlayView() }
                .tabItem { Label("Hrát", systemImage: "target") }
            NavigationStack { HistoryView() }
                .tabItem { Label("Moje hry", systemImage: "clock.arrow.circlepath") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
        }
    }
}
