import Foundation

protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

struct SystemAtomicFileWriter: AtomicFileWriting {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

struct VersionProbe: Decodable, Sendable {
    let schemaVersion: Int?
}

struct V0AlertDTO: Codable, Equatable, Sendable {
    let direction: String
    let threshold: String
    let cooldownSeconds: Int
    let hysteresisPercent: String
    let isEnabled: Bool
    let isArmed: Bool?
    let lastFiredAt: Date?
}

struct V1AlertDTO: Codable, Equatable, Sendable {
    let direction: String
    let threshold: String
    let cooldownSeconds: Int
    let hysteresisPercent: String
    let isEnabled: Bool
    let isArmed: Bool
    let lastFiredAt: Date?
}

struct MappingDTO: Codable, Equatable, Sendable {
    let exchange: String
    let productID: String
    let baseAsset: String
    let quoteAsset: String
    let provenance: String
}

struct V0ItemDTO: Codable, Equatable, Sendable {
    let id: UUID
    let coinGeckoID: String
    let symbol: String
    let name: String
    let binanceMapping: MappingDTO?
    let coinbaseMapping: MappingDTO?
    let alert: V0AlertDTO?
}

struct V1ItemDTO: Codable, Equatable, Sendable {
    let id: UUID
    let coinGeckoID: String
    let symbol: String
    let name: String
    let binanceMapping: MappingDTO?
    let coinbaseMapping: MappingDTO?
    let alert: V1AlertDTO?
}

struct V0StateDTO: Codable, Equatable, Sendable {
    let items: [V0ItemDTO]
    let primaryItemID: UUID?
}

struct V1StateDTO: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let items: [V1ItemDTO]
    let primaryItemID: UUID?
    let alertsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case items
        case primaryItemID
        case alertsEnabled
    }

    init(schemaVersion: Int, items: [V1ItemDTO], primaryItemID: UUID?, alertsEnabled: Bool = true) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.primaryItemID = primaryItemID
        self.alertsEnabled = alertsEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        items = try container.decode([V1ItemDTO].self, forKey: .items)
        primaryItemID = try container.decodeIfPresent(UUID.self, forKey: .primaryItemID)
        alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(items, forKey: .items)
        if let primaryItemID {
            try container.encode(primaryItemID, forKey: .primaryItemID)
        } else {
            try container.encodeNil(forKey: .primaryItemID)
        }
        try container.encode(alertsEnabled, forKey: .alertsEnabled)
    }
}

func migrateV0ToV1(_ old: V0StateDTO) -> V1StateDTO {
    V1StateDTO(
        schemaVersion: currentSchemaVersion,
        items: old.items.map { item in
            V1ItemDTO(
                id: item.id,
                coinGeckoID: item.coinGeckoID,
                symbol: item.symbol,
                name: item.name,
                binanceMapping: item.binanceMapping,
                coinbaseMapping: item.coinbaseMapping,
                alert: item.alert.map { alert in
                    V1AlertDTO(
                        direction: alert.direction,
                        threshold: alert.threshold,
                        cooldownSeconds: alert.cooldownSeconds,
                        hysteresisPercent: alert.hysteresisPercent,
                        isEnabled: alert.isEnabled,
                        isArmed: alert.isArmed ?? false,
                        lastFiredAt: alert.lastFiredAt
                    )
                }
            )
        },
        primaryItemID: old.primaryItemID,
        alertsEnabled: true
    )
}

enum SchemaDispatch: Equatable, Sendable {
    case version0
    case current
    case unregisteredOlder
    case newer
}

func schemaDispatch(
    version: Int,
    current: Int = currentSchemaVersion,
    registeredVersions: Set<Int> = [0, currentSchemaVersion]
) -> SchemaDispatch {
    if version == 0 { return .version0 }
    if version == current { return .current }
    if version > current { return .newer }
    if version > 0 && !registeredVersions.contains(version) { return .unregisteredOlder }
    return .unregisteredOlder
}

@MainActor
final class PersistenceStore {
    let rootDirectory: URL
    let stateURL: URL
    private let fileManager: FileManager
    private let writer: any AtomicFileWriting
    private(set) var recoveryProtected = false

    init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        writer: any AtomicFileWriting = SystemAtomicFileWriter()
    ) throws {
        self.rootDirectory = rootDirectory
        self.stateURL = rootDirectory.appendingPathComponent("watchlist.json", isDirectory: false)
        self.fileManager = fileManager
        self.writer = writer
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    static func productionRoot(fileManager: FileManager = .default) throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NetworkFailure(domain: "persistence", code: 1, message: "Application Support directory is unavailable")
        }
        return support.appendingPathComponent("BitPrice", isDirectory: true)
    }

    func load(seedID: UUID = UUID()) -> PersistenceLoadResult {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            recoveryProtected = false
            return .firstLaunch(.bitcoinSeed(id: seedID))
        }
        let original: Data
        do {
            original = try Data(contentsOf: stateURL)
        } catch {
            return recovery(original: Data(), reason: "Could not read \(stateURL.path): \(error.localizedDescription)", seedID: seedID)
        }
        do {
            let decoder = Self.makeDecoder()
            let probe = try decoder.decode(VersionProbe.self, from: original)
            let version = probe.schemaVersion ?? 0
            let state: PersistedState
            switch schemaDispatch(version: version) {
            case .version0:
                let v0 = try decoder.decode(V0StateDTO.self, from: original)
                state = try Self.domain(from: migrateV0ToV1(v0))
                try validatePersistedState(state)
                recoveryProtected = false
                return .migrated(state)
            case .current:
                let v1 = try decoder.decode(V1StateDTO.self, from: original)
                state = try Self.domain(from: v1)
            case .unregisteredOlder:
                // With current schema 1 there is no positive older integer. This branch is
                // intentionally retained and unit-tested with a simulated current version 2.
                return recovery(original: original, reason: "Schema version \(version) has no registered migration", seedID: seedID)
            case .newer:
                return recovery(original: original, reason: "Schema version \(version) is newer than this app supports", seedID: seedID)
            }
            try validatePersistedState(state)
            recoveryProtected = false
            return .loaded(state)
        } catch {
            return recovery(original: original, reason: "Invalid watchlist: \(error.localizedDescription)", seedID: seedID)
        }
    }

    func save(_ state: PersistedState, allowRecoveryReset: Bool = false) throws {
        if recoveryProtected && !allowRecoveryReset {
            throw NetworkFailure(domain: "persistence", code: 2, message: "Recovery mode preserves the original file")
        }
        try validatePersistedState(state)
        let data = try Self.makeEncoder().encode(Self.dto(from: state))
        try writer.write(data, to: stateURL)
        if allowRecoveryReset { recoveryProtected = false }
    }

    func encodedData(for state: PersistedState) throws -> Data {
        try validatePersistedState(state)
        return try Self.makeEncoder().encode(Self.dto(from: state))
    }

    private func recovery(original: Data, reason: String, seedID: UUID) -> PersistenceLoadResult {
        recoveryProtected = true
        return .recovery(seed: .bitcoinSeed(id: seedID), reason: reason, originalBytes: original)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func dto(from state: PersistedState) -> V1StateDTO {
        V1StateDTO(
            schemaVersion: state.schemaVersion,
            items: state.items.map { item in
                V1ItemDTO(
                    id: item.id,
                    coinGeckoID: item.coinGeckoID,
                    symbol: item.symbol,
                    name: item.name,
                    binanceMapping: item.binanceMapping.map(mappingDTO),
                    coinbaseMapping: item.coinbaseMapping.map(mappingDTO),
                    alert: item.alert.map { alert in
                        V1AlertDTO(
                            direction: alert.direction.rawValue,
                            threshold: decimalString(alert.threshold),
                            cooldownSeconds: alert.cooldownSeconds,
                            hysteresisPercent: decimalString(alert.hysteresisPercent),
                            isEnabled: alert.isEnabled,
                            isArmed: alert.isArmed,
                            lastFiredAt: alert.lastFiredAt
                        )
                    }
                )
            },
            primaryItemID: state.primaryItemID,
            alertsEnabled: state.alertsEnabled
        )
    }

    static func domain(from dto: V1StateDTO) throws -> PersistedState {
        PersistedState(
            schemaVersion: dto.schemaVersion,
            items: try dto.items.map { item in
                WatchItem(
                    id: item.id,
                    coinGeckoID: item.coinGeckoID,
                    symbol: item.symbol,
                    name: item.name,
                    binanceMapping: try item.binanceMapping.map(mapping),
                    coinbaseMapping: try item.coinbaseMapping.map(mapping),
                    alert: try item.alert.map { alert in
                        guard let direction = AlertDirection(rawValue: alert.direction),
                              let threshold = finiteDecimal(from: alert.threshold),
                              let hysteresis = finiteDecimal(from: alert.hysteresisPercent) else {
                            throw ValidationFailure.invalid("Invalid alert wire value")
                        }
                        return PriceAlert(
                            direction: direction,
                            threshold: threshold,
                            cooldownSeconds: alert.cooldownSeconds,
                            hysteresisPercent: hysteresis,
                            isEnabled: alert.isEnabled,
                            isArmed: alert.isArmed,
                            lastFiredAt: alert.lastFiredAt
                        )
                    }
                )
            },
            primaryItemID: dto.primaryItemID,
            alertsEnabled: dto.alertsEnabled
        )
    }

    private static func mappingDTO(_ mapping: VenueMapping) -> MappingDTO {
        MappingDTO(
            exchange: mapping.exchange.rawValue,
            productID: mapping.productID,
            baseAsset: mapping.baseAsset,
            quoteAsset: mapping.quoteAsset,
            provenance: mapping.provenance.rawValue
        )
    }

    private static func mapping(_ dto: MappingDTO) throws -> VenueMapping {
        guard let exchange = Venue(rawValue: dto.exchange),
              let provenance = MappingProvenance(rawValue: dto.provenance) else {
            throw ValidationFailure.invalid("Invalid mapping enum wire value")
        }
        return VenueMapping(
            exchange: exchange,
            productID: dto.productID,
            baseAsset: dto.baseAsset,
            quoteAsset: dto.quoteAsset,
            provenance: provenance
        )
    }
}
