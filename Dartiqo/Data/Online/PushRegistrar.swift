import Foundation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

extension Notification.Name {
    static let dartiqoPushToken = Notification.Name("dartiqo.push.token")
}

/// Stejný postup jako Privofit: FirebaseMessaging až po skutečném APNS tokenu, pak FCM token na server.
final class PushRegistrar: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    static weak var shared: PushRegistrar?
    private var firebaseReady = false
    private var hasRealAPNSToken = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.shared = self
        firebaseReady = configureFirebaseIfPossible()
        if firebaseReady {
            Messaging.messaging().delegate = self
            print("[FCM] Firebase připraven")
        } else {
            print("[FCM] Chybí GoogleService-Info.plist – FCM token až po přidání Firebase projektu Dartiqo")
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func registerForPushes() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("[FCM] APNS token přijat (\(deviceToken.count) B), předávám FCM…")
        hasRealAPNSToken = true
        guard firebaseReady else { return }
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            DispatchQueue.main.async {
                if let error {
                    print("[FCM] Chyba při načtení tokenu: \(error.localizedDescription)")
                    return
                }
                guard let token, !token.isEmpty else { return }
                print("[FCM] FCM token přijat")
                NotificationCenter.default.post(name: .dartiqoPushToken, object: token)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        hasRealAPNSToken = false
        print("[FCM] APNS registrace selhala: \(error.localizedDescription)")
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty, messaging.apnsToken != nil else { return }
        Task { @MainActor in
            guard self.hasRealAPNSToken else { return }
            NotificationCenter.default.post(name: .dartiqoPushToken, object: fcmToken)
        }
    }

    func currentToken() -> String? {
        guard firebaseReady, hasRealAPNSToken, Messaging.messaging().apnsToken != nil,
              let token = Messaging.messaging().fcmToken, !token.isEmpty else { return nil }
        return token
    }

    private func configureFirebaseIfPossible() -> Bool {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let appID = plist["GOOGLE_APP_ID"] as? String, !appID.isEmpty,
              appID.contains(":ios:") else { return false }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return FirebaseApp.app() != nil
    }
}
