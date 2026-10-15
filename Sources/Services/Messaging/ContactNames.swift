import AppKit
import Contacts
import Foundation
import os

/// Names for Messages handles (phone numbers and email addresses) from your
/// Contacts, so a new message reads "Sam Lee", not "+1 (555) 010-2030".
///
/// Contacts access is asked for only once incoming Messages is on and a message
/// arrives from a handle; without it, the handle shows as before. Lookups run
/// off the main thread and are cached for the session.
final class ContactNames: @unchecked Sendable {
    static let shared = ContactNames()

    private let store = CNContactStore()
    private struct State {
        var names: [String: String?] = [:]
        var photos: [String: NSImage?] = [:]
        var asked = false
    }
    /// An unfair lock is safe to take from async code (an NSLock isn't).
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// A handle that is a phone number or email address rather than a name.
    static func isHandle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@") { return true }
        let digits = trimmed.filter(\.isNumber)
        return digits.count >= 5 && trimmed.allSatisfy { $0.isNumber || " +-().".contains($0) }
    }

    /// The contact's name for a handle, asking for access the first time.
    func name(for handle: String) async -> String? {
        guard Self.isHandle(handle) else { return nil }
        if let cached = state.withLock({ $0.names[handle] }) { return cached }
        guard await authorized() else { return nil }
        let name = lookup(handle)
        state.withLock { $0.names[handle] = name }
        return name
    }

    /// The contact's photo for a handle, if they have one (only once Contacts access exists).
    func photo(for handle: String) async -> NSImage? {
        guard Self.isHandle(handle) else { return nil }
        if let cached = state.withLockUnchecked({ $0.photos[handle] }) { return cached }
        guard await authorized() else { return nil }
        let keys: [CNKeyDescriptor] = [CNContactThumbnailImageDataKey as CNKeyDescriptor, CNContactImageDataAvailableKey as CNKeyDescriptor]
        let predicate = handle.contains("@")
            ? CNContact.predicateForContacts(matchingEmailAddress: handle)
            : CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        let image = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys))?
            .first(where: \.imageDataAvailable)?.thumbnailImageData.flatMap(NSImage.init(data:))
        state.withLockUnchecked { $0.photos[handle] = image }
        return image
    }

    private func authorized() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return true
        case .notDetermined:
            let first = state.withLock { state -> Bool in
                defer { state.asked = true }
                return !state.asked
            }
            guard first else { return false }
            return (try? await store.requestAccess(for: .contacts)) ?? false
        default:
            return false
        }
    }

    private func lookup(_ handle: String) -> String? {
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                       CNContactNicknameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor]
        let predicate = handle.contains("@")
            ? CNContact.predicateForContacts(matchingEmailAddress: handle)
            : CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        guard let contact = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first else { return nil }
        if let full = CNContactFormatter.string(from: contact, style: .fullName), !full.isEmpty { return full }
        if !contact.nickname.isEmpty { return contact.nickname }
        return contact.organizationName.isEmpty ? nil : contact.organizationName
    }
}
