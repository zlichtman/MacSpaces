import Foundation
import Combine

/// Owns the Nook and reconciles only the services its active profile needs.
@MainActor
final class ModuleCoordinator {
    private let settings = AppSettings.shared
    private let nookSettings = NookSettings.shared
    private var notchManager: NotchManager?
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        apply()
        settings.$notchEnabled.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        nookSettings.objectWillChange.debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.nookSettings.isInteractiveReorderActive == false else { return }
                DispatchQueue.main.async { self?.applyServiceDemand() }
            }.store(in: &cancellables)
    }
    private func apply() {
        applyServiceDemand()
        if settings.notchEnabled {
            if notchManager == nil { notchManager = NotchManager(); notchManager?.start() }
        } else { notchManager?.stop(); notchManager = nil }
    }
    private func applyServiceDemand() {
        AppServices.shared.reconcileDemand(app: settings, nook: nookSettings)
    }
}
