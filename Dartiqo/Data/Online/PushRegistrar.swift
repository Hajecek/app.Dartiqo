import Foundation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

extension Notification.Name {
    static let dartiqoPushToken = Notification.Name("dartiqo.push.token")
    static let dartiqoPushReceived = Notification.Name("dartiqo.push.received")
    static let dartiqoPushOpened = Notification.Name("dartiqo.push.opened")
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
                guard let token, !token.isEmpty else {
                    print("[FCM] FCM token je prázdný")
                    return
                }
                self.publish(token)
            }
        }
    }

    private func publish(_ token: String) {
        print("[FCM] FCM token: \(token)")
        NotificationCenter.default.post(name: .dartiqoPushToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        hasRealAPNSToken = false
        print("[FCM] APNS registrace selhala: \(error.localizedDescription)")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = Self.payload(notification.request.content.userInfo)
        NotificationCenter.default.post(name: .dartiqoPushReceived, object: nil, userInfo: payload)
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let payload = Self.payload(response.notification.request.content.userInfo)
        Task { @MainActor in
            Self.pendingRoute = payload["type"] as? String
            NotificationCenter.default.post(name: .dartiqoPushOpened, object: nil, userInfo: payload)
        }
        completionHandler()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(name: .dartiqoPushReceived, object: nil, userInfo: Self.payload(userInfo))
        completionHandler(.newData)
    }

    /// Klepnutí na notifikaci ještě před tím, než SwiftUI stihne poslouchat.
    @MainActor static var pendingRoute: String?

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty, messaging.apnsToken != nil else { return }
        Task { @MainActor in
            guard self.hasRealAPNSToken else { return }
            self.publish(fcmToken)
        }
    }

    func currentToken() -> String? {
        guard firebaseReady, hasRealAPNSToken, Messaging.messaging().apnsToken != nil,
              let token = Messaging.messaging().fcmToken, !token.isEmpty else { return nil }
        return token
    }

    private func configureFirebaseIfPossible() -> Bool {
        for name in ["GoogleService-Info", "GoogleService-Info-dartiqo"] {
            guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: path),
                  options.googleAppID.contains(":ios:") else { continue }
            if FirebaseApp.app() == nil {
                FirebaseApp.configure(options: options)
            }
            return FirebaseApp.app() != nil
        }
        return false
    }

    nonisolated private static func payload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let type = userInfo["type"] as? String, !type.isEmpty {
            payload["type"] = type
        }
        if payload["type"] == nil, let data = userInfo["data"] as? [AnyHashable: Any],
           let type = data["type"] as? String, !type.isEmpty {
            payload["type"] = type
        }
        return payload
    }
}
