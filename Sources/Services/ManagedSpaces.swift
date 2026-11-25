import Foundation

/// The window server's private list of Spaces, found at run time so a macOS without it
/// loses only what needs it: `SpacesMonitor`, and Tape's desktops, which reads it on its own worker. Nothing here asks for a permission.
enum ManagedSpaces {
    typealias MainConnection = @convention(c) () -> Int32
    typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    static let symbols: (connection: MainConnection, copy: CopySpaces)? = {
        // RTLD_DEFAULT, which Swift doesn't import: CoreGraphics is already loaded.
        let loaded = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(loaded, "CGSMainConnectionID"),
              let copy = dlsym(loaded, "CGSCopyManagedDisplaySpaces") else { return nil }
        return (unsafeBitCast(connection, to: MainConnection.self), unsafeBitCast(copy, to: CopySpaces.self))
    }()

    static func read() -> [SpaceDisplay]? {
        guard let symbols, let list = symbols.copy(symbols.connection()) else { return nil }
        return SpaceLayout.parse(list.takeRetainedValue() as NSArray)
    }
}
