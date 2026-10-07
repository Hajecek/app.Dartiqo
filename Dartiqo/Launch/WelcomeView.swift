import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @FocusState private var focused: Bool

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tvoje další velká hra.")
                        .font(.largeTitle.bold())
                    Text("Kamarádi, soupeři a osobní rekordy. Všechno začíná jednou šipkou.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                if !store.data.profiles.isEmpty { existingProfiles }
                createProfile
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Theme.brand)
            DartboardArt()
                .colorMultiply(.black)
                .opacity(0.12)
                .frame(height: 320)
                .offset(x: 110, y: 70)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                    .accessibilityHidden(true)
                Spacer(minLength: 24)
                Text("Dartiqo")
                    .font(.largeTitle.bold())
                Text("Hra začíná u tebe.")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.black)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var existingProfiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Pokračovat s profilem")
            ForEach(store.data.profiles) { profile in
                Button { store.select(profile) } label: {
                    HStack(spacing: 12) {
                        Avatar(name: profile.name, photo: profile.photoJPEG)
                        Text(profile.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .surface()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var createProfile: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Tvoje přezdívka", text: $name)
                .textContentType(.nickname)
                .padding(16)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { if canCreate { store.createProfile(name) } }
            Button {
                focused = false
                store.createProfile(name)
            } label: {
                Text("Vytvořit hráčský profil")
            }
            .buttonStyle(PrimaryButton())
            .disabled(!canCreate)
            .opacity(canCreate ? 1 : 0.45)
            Text("Místní profil bez hesla. Hry zůstávají v tomto zařízení, nejde o online účet. Profil můžeš chránit pomocí Face ID nebo kódu zařízení.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
