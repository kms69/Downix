import Foundation

/// The queue chosen in the sidebar's QUEUES section (nil = no queue filter).
@MainActor
final class QueueSelection: ObservableObject {
    static let shared = QueueSelection()
    @Published var queueID: UUID?
    private init() {}
}
