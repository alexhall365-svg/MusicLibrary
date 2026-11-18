import Foundation
import CloudKit
import SwiftData
import UIKit

enum ChoirError: LocalizedError {
    case notAvailable
    case alreadyHosting

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "iCloud isn't available. Check you're signed in to iCloud and connected to the internet."
        case .alreadyHosting:
            return "You already host a Choir Library."
        }
    }
}

/// Creating, sharing, joining and leaving Choir Libraries.
extension CloudSync {
    /// Creates your Choir Library: a zone in your iCloud, shared with a `CKShare`
    /// that you then send to the choir. Needs a connection.
    func createChoir(named name: String) async throws -> ChoirInfo {
        guard let container = cloudContainer, isEnabled else { throw ChoirError.notAvailable }
        // One hosted choir for now. The storage allows several (each is its own
        // zone), so this limit can be lifted later without changing the data.
        guard hostedChoir == nil else { throw ChoirError.alreadyHosting }
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: CloudLibrary.hostedZonePrefix + UUID().uuidString.prefix(8))
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = name
        share.publicPermission = .readOnly
        _ = try await database.modifyRecords(saving: [share], deleting: [])

        let info = ChoirInfo(
            id: CloudLibrary.hostedKey(zoneName: zone.zoneID.zoneName),
            name: name, isOwner: true, canEdit: true, ownerName: nil)
        upsertChoir(info)
        return info
    }

    /// Makes sure the choir is shared as "anyone with the link can view" (older
    /// choirs were invite-only), and returns the share.
    @discardableResult
    func ensureLinkSharing(_ library: String) async throws -> CKShare? {
        guard let share = try await fetchShare(for: library) else { return nil }
        guard CloudLibrary.isHosted(library), share.publicPermission != .readOnly,
              let container = cloudContainer else { return share }
        share.publicPermission = .readOnly
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if case .success(let saved)? = result.saveResults[share.recordID], let savedShare = saved as? CKShare {
            note("Choir now shared as anyone with the link (view only)")
            return savedShare
        }
        return share
    }

    func renameChoir(_ library: String, to name: String) async throws {
        let clean = name.trimmed
        guard !clean.isEmpty, let share = try await fetchShare(for: library),
              let container = cloudContainer else { return }
        share[CKShare.SystemFieldKey.title] = clean
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if var info = choir(library) {
            info.name = clean
            upsertChoir(info)
        }
    }

    func fetchShare(for library: String) async throws -> CKShare? {
        guard let container = cloudContainer else { throw ChoirError.notAvailable }
        let location = CloudLibrary.location(of: library)
        let database = location.scope == .shared ? container.sharedCloudDatabase : container.privateCloudDatabase
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: location.zoneID)
        return try await database.record(for: id) as? CKShare
    }

    /// Deletes your Choir Library for everyone. Its music and lists move into
    /// your own library on this device, so nothing of yours is lost.
    func deleteHostedChoir(_ library: String) {
        guard CloudLibrary.isHosted(library) else { return }
        let zoneID = CloudLibrary.location(of: library).zoneID
        moveLibraryToPersonal(library)
        addPendingZoneDelete(zoneID)
        scheduleScan(after: 0.5)
    }

    /// Leaves a choir you joined. Its music is removed from your devices.
    func leaveChoir(_ library: String) async throws {
        guard CloudLibrary.isJoined(library), let container = cloudContainer else { return }
        let zoneID = CloudLibrary.location(of: library).zoneID
        // Deleting a shared zone from your shared database removes you from the share.
        _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
        removeLibraryLocally(library)
    }

    /// Accepts an invitation opened from Messages, Mail or a link.
    func accept(_ metadata: CKShare.Metadata) async {
        guard let container = cloudContainer,
              metadata.containerIdentifier == container.containerIdentifier else {
            problem = "This invitation is for a different app."
            return
        }
        guard metadata.participantRole != .owner else { return }
        do {
            _ = try await container.accept(metadata)
            let zoneID = metadata.share.recordID.zoneID
            let library = CloudLibrary.key(for: zoneID, scope: .shared) ?? ""
            updateChoir(library, from: metadata.share)
            if var info = choir(library) {
                info.canEdit = metadata.participantPermission == .readWrite
                upsertChoir(info)
            }
            await fetchShared()
        } catch {
            report(error)
        }
    }
}

// MARK: - Apple's sharing screen

/// Shows Apple's screen for inviting people and choosing who can edit.
@MainActor
final class ChoirSharingPresenter: NSObject, UICloudSharingControllerDelegate {
    static let shared = ChoirSharingPresenter()
    private var choirName = ""
    private var library = ""

    func present(library: String) async {
        let sync = CloudSync.shared
        guard let container = sync.cloudContainer else { return }
        do {
            guard let share = try await sync.ensureLinkSharing(library) else { return }
            choirName = sync.choir(library)?.name ?? "Choir Library"
            self.library = library
            let controller = UICloudSharingController(share: share, container: container)
            // Always "Anyone with the link can view": no matching of invitees'
            // Apple Account emails, and nobody but the owner can change anything.
            controller.availablePermissions = [.allowPublic, .allowReadOnly]
            controller.delegate = self
            guard let presenter = Self.topViewController() else { return }
            if let popover = controller.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            presenter.present(controller, animated: true)
        } catch {
            sync.report(error)
        }
    }

    nonisolated func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        Task { @MainActor in CloudSync.shared.report(error) }
    }

    nonisolated func itemTitle(for csc: UICloudSharingController) -> String? {
        MainActor.assumeIsolated { choirName }
    }

    nonisolated func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        Task { @MainActor in
            await CloudSync.shared.refreshChoirDetails(library)
        }
    }

    nonisolated func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        // Stopping sharing deletes the share. Make a fresh one so the Choir
        // Library can be shared again later.
        Task { @MainActor in
            let sync = CloudSync.shared
            guard let container = sync.cloudContainer else { return }
            let zoneID = CloudLibrary.location(of: library).zoneID
            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = choirName
            share.publicPermission = .readOnly
            _ = try? await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
            await sync.refreshChoirDetails(library)
        }
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Opening invitations

/// Receives accepted CloudKit invitations (SwiftUI has no hook for them).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if CloudSync.shared.isSupported {
            // Lets iCloud tell the app about changes made on other devices.
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in
                // Give the app a moment to finish starting.
                try? await Task.sleep(for: .seconds(1))
                await CloudSync.shared.accept(metadata)
            }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            await CloudSync.shared.accept(metadata)
        }
    }
}
