import Foundation

extension Notification.Name {
    /// Navigate to a sidebar section (object: SidebarSection)
    static let navigateToSection = Notification.Name("navigateToSection")

    /// Open the new recipe editor
    static let newRecipeRequested = Notification.Name("newRecipeRequested")

    /// Open the URL import sheet
    static let importFromURLRequested = Notification.Name("importFromURLRequested")

    /// Open the settings sheet
    static let openSettingsRequested = Notification.Name("openSettingsRequested")

    /// A CloudKit share was just accepted — steer to the shared Plan so a new
    /// member lands on the household week, not their own empty Log.
    static let shareAccepted = Notification.Name("shareAccepted")
}
