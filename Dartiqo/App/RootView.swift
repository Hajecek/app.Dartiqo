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
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.section) {
            NavigationStack { HomeView() }
                .id(store.homeGeneration)
                .tabItem { Label("Domů", systemImage: "house.fill") }
                .tag(AppSection.home)
            NavigationStack { PlayView() }
                .id(store.homeGeneration)
                .tabItem { Label("Hrát", systemImage: "target") }
                .tag(AppSection.play)
            NavigationStack { HistoryView() }
                .tabItem { Label("Moje hry", systemImage: "clock.arrow.circlepath") }
                .tag(AppSection.games)
            NavigationStack { ProfileView() }
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppSection.profile)
            NavigationStack { SettingsView() }
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
                .tag(AppSection.settings)
        }
    }
}
