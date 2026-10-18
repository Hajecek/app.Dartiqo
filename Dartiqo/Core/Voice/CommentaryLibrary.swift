import AVFoundation
import Foundation

/// Nahrávky komentáře na disku, jedna na situaci a hráčský profil.
@MainActor
final class CommentaryLibrary: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private let fileManager = FileManager.default

    func folder(for owner: UUID) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dartiqo", isDirectory: true)
            .appendingPathComponent("commentary", isDirectory: true)
            .appendingPathComponent(owner.uuidString, isDirectory: true)
    }

    func fileURL(owner: UUID, cue: CommentaryCue) -> URL {
        folder(for: owner).appendingPathComponent(cue.id).appendingPathExtension("m4a")
    }

    func exists(owner: UUID, cue: CommentaryCue) -> Bool {
        fileManager.fileExists(atPath: fileURL(owner: owner, cue: cue).path)
    }

    func recordedIDs(owner: UUID) -> Set<String> {
        let folder = folder(for: owner)
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return Set(urls.filter { $0.pathExtension == "m4a" }.map { $0.deletingPathExtension().lastPathComponent })
    }

    func count(owner: UUID) -> Int {
        let ids = recordedIDs(owner: owner)
        return CommentaryCue.all.filter { ids.contains($0.id) }.count
    }

    func save(owner: UUID, cue: CommentaryCue, from source: URL) throws {
        let folder = folder(for: owner)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = fileURL(owner: owner, cue: cue)
        let staging = destination.appendingPathExtension("staging")
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    func delete(owner: UUID, cue: CommentaryCue) {
        let url = fileURL(owner: owner, cue: cue)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    func deleteAll(owner: UUID) {
        let folder = folder(for: owner)
        guard fileManager.fileExists(atPath: folder.path) else { return }
        try? fileManager.removeItem(at: folder)
    }

    /// Pustí první uloženou situaci z pořadí. `false` = žádný klip, ať mluví výchozí hlas.
    @discardableResult
    func play(owner: UUID, cues: [CommentaryCue]) -> Bool {
        guard let url = cues.map({ fileURL(owner: owner, cue: $0) }).first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return false
        }
        player?.stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            next.prepareToPlay()
            guard next.play() else { return false }
            player = next
            return true
        } catch {
            return false
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
