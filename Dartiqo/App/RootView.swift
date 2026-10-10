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
            NavigationStack {
                SetupView(mode: .x01) {
                    store.section = .home
                }
            }
                .id(store.homeGeneration)
                .tabItem { Label("Hrát", systemImage: "target") }
                .tag(AppSection.play)
            NavigationStack {
                TrainingHomeView {
                    store.section = .home
                }
            }
                .tabItem { Label("Trénink", systemImage: "scope") }
                .tag(AppSection.training)
            NavigationStack { HistoryView() }
                .tabItem { Label("Moje hry", systemImage: "clock.arrow.circlepath") }
                .tag(AppSection.games)
            NavigationStack { ProfileView() }
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppSection.profile)
        }
    }
}
