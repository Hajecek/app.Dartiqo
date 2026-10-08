import SwiftUI
import Contacts
import ContactsUI

struct PickedFriend: Identifiable, Equatable {
    var id: UUID
    var name: String
}

/// Pozvání soupeřů, kteří hrají na stejném telefonu.
struct FriendPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var taken: Set<UUID>
    var slots: Int
    var onPick: ([PickedFriend]) -> Void

    @State private var selected: [PickedFriend] = []
    @State private var newName = ""
    @State private var showContacts = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("Jméno nového přítele", text: $newName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($typing)
                            .submitLabel(.done)
                            .onSubmit(addTyped)
                        Button("Přidat", action: addTyped)
                            .fontWeight(.semibold)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button { showContacts = true } label: {
                        Label("Vybrat z kontaktů", systemImage: "person.crop.circle.badge.plus")
                    }
                } footer: {
                    Text("Přítel se uloží jen v tomhle telefonu. Příště ho najdeš tady.")
                }

                if !store.housemates.isEmpty {
                    Section("Profily na tomto telefonu") {
                        ForEach(store.housemates) { profile in
                            row(PickedFriend(id: profile.id, name: profile.name), detail: "Statistiky se uloží i do jeho profilu", photo: profile.photoJPEG)
                        }
                    }
                }

                Section("Přátelé") {
                    if store.friends.isEmpty {
                        Text("Zatím žádní přátelé. Přidej jméno nahoře nebo z kontaktů.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.friends) { friend in
                        row(PickedFriend(id: friend.id, name: friend.name), detail: friend.lastPlayed.map { "Naposledy \($0.formatted(.relative(presentation: .named)))" } ?? "Ještě jste spolu nehráli", photo: nil)
                            .swipeActions {
                                Button("Smazat", role: .destructive) {
                                    selected.removeAll { $0.id == friend.id }
                                    store.deleteFriend(friend.id)
                                }
                            }
                    }
                }
            }
            .navigationTitle("Pozvat přátele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Přidat" : "Přidat (\(selected.count))") {
                        onPick(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty)
                }
            }
            .sheet(isPresented: $showContacts) {
                ContactPicker { names in
                    for name in names { if let friend = store.addFriend(name) { toggle(PickedFriend(id: friend.id, name: friend.name), forceOn: true) } }
                }
                .ignoresSafeArea()
            }
            .sensoryFeedback(.selection, trigger: selected)
        }
        .presentationDetents([.medium, .large])
    }

    private var full: Bool { selected.count >= slots }

    private func row(_ friend: PickedFriend, detail: String, photo: Data?) -> some View {
        let inRoster = taken.contains(friend.id)
        let isOn = selected.contains { $0.id == friend.id }
        return Button { toggle(friend) } label: {
            HStack(spacing: 12) {
                Avatar(name: friend.name, size: 40, photo: photo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(inRoster ? "Už hraje" : detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn || inRoster ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.action : Color.secondary.opacity(inRoster ? 0.5 : 1))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inRoster || (full && !isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ friend: PickedFriend, forceOn: Bool = false) {
        guard !taken.contains(friend.id) else { return }
        if let index = selected.firstIndex(where: { $0.id == friend.id }) {
            if !forceOn { selected.remove(at: index) }
        } else if !full {
            selected.append(friend)
        }
    }

    private func addTyped() {
        guard let friend = store.addFriend(newName) else { return }
        newName = ""
        typing = false
        toggle(friend.asPicked, forceOn: true)
    }
}

private extension Friend {
    var asPicked: PickedFriend { PickedFriend(id: id, name: name) }
}

/// Systémový výběr kontaktů. Aplikace nepotřebuje přístup ke všem kontaktům.
struct ContactPicker: UIViewControllerRepresentable {
    var onPick: ([String]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey]
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([String]) -> Void
        init(onPick: @escaping ([String]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let names = contacts.compactMap { contact -> String? in
                let nick = contact.nickname.trimmingCharacters(in: .whitespaces)
                if !nick.isEmpty { return nick }
                let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                return full.isEmpty ? nil : full
            }
            onPick(names)
        }
    }
}
