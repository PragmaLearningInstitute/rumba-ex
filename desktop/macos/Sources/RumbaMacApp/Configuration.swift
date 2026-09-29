import Foundation
import PostgresNIO
import NIOSSL

struct AppConfiguration {
    let dbHost: String
    let dbPort: Int
    let dbUser: String
    let dbPassword: String
    let dbName: String
    let useTLS: Bool
    let enableLocalFallback: Bool

    static func loadFromEnvironment() -> AppConfiguration {
        let env = ProcessInfo.processInfo.environment
        return AppConfiguration(
            dbHost: env["RUMBA_DB_HOST"] ?? "127.0.0.1",
            dbPort: Int(env["RUMBA_DB_PORT"] ?? "5432") ?? 5432,
            dbUser: env["RUMBA_DB_USER"] ?? "postgres",
            dbPassword: env["RUMBA_DB_PASSWORD"] ?? "",
            dbName: env["RUMBA_DB_NAME"] ?? "rumba_dev",
            useTLS: !["127.0.0.1", "localhost", "::1"].contains(env["RUMBA_DB_HOST"] ?? "127.0.0.1") || (env["RUMBA_DB_TLS"] ?? "false").lowercased() == "true",
            enableLocalFallback: (env["RUMBA_ENABLE_LOCAL_FALLBACK"] ?? "false").lowercased() == "true"
        )
    }

    var postgresConfiguration: PostgresClient.Configuration {
        let tlsMode: PostgresClient.Configuration.TLS
        if useTLS {
            tlsMode = .require(TLSConfiguration.makeClientConfiguration())
        } else {
            tlsMode = .disable
        }

        return PostgresClient.Configuration(
            host: dbHost,
            port: dbPort,
            username: dbUser,
            password: dbPassword,
            database: dbName,
            tls: tlsMode
        )
    }
}
