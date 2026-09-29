import Foundation
import PostgresNIO

@MainActor
final class PostgresService {
    let client: PostgresClient
    private let runTask: Task<Void, Never>

    init(configuration: AppConfiguration) {
        let client = PostgresClient(configuration: configuration.postgresConfiguration)
        self.client = client
        self.runTask = Task {
            await client.run()
        }
    }

    deinit {
        runTask.cancel()
    }

    func shutdown() {
        runTask.cancel()
    }

    func ping() async -> Bool {
        do {
            _ = try await client.query("SELECT 1;")
            return true
        } catch {
            return false
        }
    }
}
