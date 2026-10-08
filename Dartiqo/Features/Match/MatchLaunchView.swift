import SwiftUI

/// Úvod s logem před novým zápasem. Po krátké chvíli se rovnou otevře hra.
struct MatchLaunchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var intro = true

    @State private var ready = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if ready || !intro {
                NavigationStack { MatchView() }
                    .transition(.opacity)
            } else {
                splash
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: ready)
        .task {
            guard intro, !ready else { return }
            pulse = true
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            ready = true
        }
    }

    private var splash: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("Logo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                .scaleEffect(pulse && !reduceMotion ? 1.06 : 0.94)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .accessibilityLabel("Dartiqo")
            if let match = store.activeMatch {
                VStack(spacing: 8) {
                    Text(match.players.map(\.name).joined(separator: " vs "))
                        .font(AppFont.title(22))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(caption(match))
                        .font(AppFont.body(15))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Text("Začíná \(match.players[match.starter].name)")
                        .font(AppFont.caption(14, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                }
                .padding(.horizontal, 32)
            }
            Spacer()
            ProgressView()
                .tint(.white)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Načítám zápas")
    }

    private func caption(_ match: Match) -> String {
        let mode = match.config.mode
        if mode == .x01 || mode == .cricket { return "\(mode.shortTitle) · \(match.config.lengthLine)" }
        return match.config.summary
    }
}
