import Foundation
import Combine

/// Starts and stops the Notch and Dock modules as their toggles change.
@MainActor
final class ModuleCoordinator {
    private let settings = AppSettings.shared
    private let nookSettings = NookSettings.shared
    private let dockStore = DockStore.shared
    private var notchManager: NotchManager?
    private var dockController: DockController?
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        apply()

        settings.$notchEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        settings.$dockEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        nookSettings.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.nookSettings.isInteractiveReorderActive == false else { return }
                DispatchQueue.main.async { self?.applyServiceDemand() }
            }
            .store(in: &cancellables)

        dockStore.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.dockStore.isInteractiveReorderActive == false else { return }
                DispatchQueue.main.async { self?.applyServiceDemand() }
            }
            .store(in: &cancellables)
    }

    private func apply() {
        // Resolve service state before presenting surfaces that derive their
        // initial geometry from it.
        applyServiceDemand()

        if settings.notchEnabled {
            if notchManager == nil {
                notchManager = NotchManager()
                notchManager?.start()
            }
        } else {
            notchManager?.stop()
            notchManager = nil
        }

        if settings.dockEnabled {
            if dockController == nil {
                dockController = DockController(store: .shared)
                dockController?.start()
            }
        } else {
            dockController?.stop()
            dockController = nil
        }
    }

    private func applyServiceDemand() {
        AppServices.shared.reconcileDemand(
            app: settings,
            nook: nookSettings,
            dock: dockStore
        )
    }
}
