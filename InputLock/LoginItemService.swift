import Foundation
import ServiceManagement
import Combine

@MainActor
final class LoginItemService: ObservableObject {

    @Published var enabled: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ newValue: Bool) {
        do {
            if newValue {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Surface failures by reverting to the system-reported state.
        }
        refresh()
    }
}
