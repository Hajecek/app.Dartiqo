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
    @StateObject private var setupChrome = MatchSetupChrome()

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
        .environmentObject(setupChrome)
        .tabBarMinimizeBehavior(setupChrome.title != nil ? .onScrollDown : .automatic)
        .tabViewBottomAccessory(isEnabled: setupChrome.title != nil) {
            SetupAccessoryButton()
                .environmentObject(setupChrome)
        }
    }
}

/// Akce nového zápasu, kterou spodní menu ukáže jen dokud je průvodce otevřený.
@MainActor final class MatchSetupChrome: ObservableObject {
    @Published var title: String?
    @Published var enabled = false
    @Published var token = 0
    var owner: UUID?
}
