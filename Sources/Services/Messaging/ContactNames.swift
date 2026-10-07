import AppKit
import Contacts
import Foundation

/// Names for Messages handles (phone numbers and email addresses) from your
/// Contacts, so a new message reads "Sam Lee", not "+1 (555) 010-2030".
///
/// Contacts access is asked for only once incoming Messages is on and a message
/// arrives from a handle; without it, the handle shows as before. Lookups run
/// off the main thread and are cached for the session.
final class ContactNames: @unchecked Sendable {
    static let shared = ContactNames()

    private let store = CNContactStore()
    private let lock = NSLock()
    private var cache: [String: String?] = [:]
    private var photos: [String: NSImage?] = [:]
    private var asked = false

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
        lock.lock()
        if let cached = cache[handle] { lock.unlock(); return cached }
        lock.unlock()
        guard await authorized() else { return nil }
        let name = lookup(handle)
        lock.lock(); cache[handle] = name; lock.unlock()
        return name
    }

    /// The contact's photo for a handle, if they have one (only once Contacts access exists).
    func photo(for handle: String) async -> NSImage? {
        guard Self.isHandle(handle) else { return nil }
        lock.lock()
        if let cached = photos[handle] { lock.unlock(); return cached }
        lock.unlock()
        guard await authorized() else { return nil }
        let keys: [CNKeyDescriptor] = [CNContactThumbnailImageDataKey as CNKeyDescriptor, CNContactImageDataAvailableKey as CNKeyDescriptor]
        let predicate = handle.contains("@")
            ? CNContact.predicateForContacts(matchingEmailAddress: handle)
            : CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        let image = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys))?
            .first(where: \.imageDataAvailable)?.thumbnailImageData.flatMap(NSImage.init(data:))
        lock.lock(); photos[handle] = image; lock.unlock()
        return image
    }

    private func authorized() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return true
        case .notDetermined:
            lock.lock()
            let first = !asked
            asked = true
            lock.unlock()
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
