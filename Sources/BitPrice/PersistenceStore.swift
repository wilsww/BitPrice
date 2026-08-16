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

struct V2ItemDTO: Codable, Equatable, Sendable {
    let id: UUID
    let coinGeckoID: String
    let symbol: String
    let name: String
    let mapping: MappingDTO?
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
    let textSize: String
    let chartRange: String
    let defaultAlertCooldownSeconds: Int
    let defaultAlertHysteresisPercent: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case items
        case primaryItemID
        case alertsEnabled
        case textSize
        case chartRange
        case defaultAlertCooldownSeconds
        case defaultAlertHysteresisPercent
    }

    init(
        schemaVersion: Int,
        items: [V1ItemDTO],
        primaryItemID: UUID?,
        alertsEnabled: Bool = true,
        textSize: String = TextSizePreference.medium.rawValue,
        chartRange: String = ChartRange.hours24.rawValue,
        defaultAlertCooldownSeconds: Int = 30,
        defaultAlertHysteresisPercent: String = "10"
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.primaryItemID = primaryItemID
        self.alertsEnabled = alertsEnabled
        self.textSize = TextSizePreference(rawValue: textSize)?.rawValue ?? TextSizePreference.medium.rawValue
        self.chartRange = ChartRange(rawValue: chartRange)?.rawValue ?? ChartRange.hours24.rawValue
        self.defaultAlertCooldownSeconds = defaultAlertCooldownSeconds
        self.defaultAlertHysteresisPercent = defaultAlertHysteresisPercent
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        items = try container.decode([V1ItemDTO].self, forKey: .items)
        primaryItemID = try container.decodeIfPresent(UUID.self, forKey: .primaryItemID)
        alertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        let decodedTextSize = try container.decodeIfPresent(String.self, forKey: .textSize)
            ?? TextSizePreference.medium.rawValue
        textSize = TextSizePreference(rawValue: decodedTextSize)?.rawValue ?? TextSizePreference.medium.rawValue
        let decodedChartRange = try container.decodeIfPresent(String.self, forKey: .chartRange)
            ?? ChartRange.hours24.rawValue
        chartRange = ChartRange(rawValue: decodedChartRange)?.rawValue ?? ChartRange.hours24.rawValue
        defaultAlertCooldownSeconds = try container.decodeIfPresent(Int.self, forKey: .defaultAlertCooldownSeconds) ?? 30
        defaultAlertHysteresisPercent = try container.decodeIfPresent(String.self, forKey: .defaultAlertHysteresisPercent) ?? "10"
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
        try container.encode(textSize, forKey: .textSize)
        try container.encode(chartRange, forKey: .chartRange)
        try container.encode(defaultAlertCooldownSeconds, forKey: .defaultAlertCooldownSeconds)
        try container.encode(defaultAlertHysteresisPercent, forKey: .defaultAlertHysteresisPercent)
    }
}

struct V2StateDTO: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let items: [V2ItemDTO]
    let primaryItemID: UUID?
    let alertsEnabled: Bool
    let textSize: String
    let chartRange: String
    let defaultAlertCooldownSeconds: Int
    let defaultAlertHysteresisPercent: String
}

func migrateV0ToV1(_ old: V0StateDTO) -> V1StateDTO {
    V1StateDTO(
        schemaVersion: 1,
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
        alertsEnabled: true,
        textSize: TextSizePreference.medium.rawValue,
        chartRange: ChartRange.hours24.rawValue,
        defaultAlertCooldownSeconds: 30,
        defaultAlertHysteresisPercent: "10"
    )
}

func migrateV1ToV2(_ old: V1StateDTO) throws -> V2StateDTO {
    let binanceIDs = old.items.compactMap(\.binanceMapping?.productID)
    let coinbaseIDs = old.items.compactMap(\.coinbaseMapping?.productID)
    guard Set(binanceIDs).count == binanceIDs.count else {
        throw ValidationFailure.invalid("Duplicate Binance product ID")
    }
    guard Set(coinbaseIDs).count == coinbaseIDs.count else {
        throw ValidationFailure.invalid("Duplicate Coinbase product ID")
    }
    return V2StateDTO(
        schemaVersion: currentSchemaVersion,
        items: try old.items.map { item in
            try validateLegacyMapping(item.binanceMapping, expectedVenue: .binance)
            try validateLegacyMapping(item.coinbaseMapping, expectedVenue: .coinbase)
            return V2ItemDTO(
                id: item.id,
                coinGeckoID: item.coinGeckoID,
                symbol: item.symbol,
                name: item.name,
                mapping: item.binanceMapping ?? item.coinbaseMapping,
                alert: item.alert
            )
        },
        primaryItemID: old.primaryItemID,
        alertsEnabled: old.alertsEnabled,
        textSize: old.textSize,
        chartRange: old.chartRange,
        defaultAlertCooldownSeconds: old.defaultAlertCooldownSeconds,
        defaultAlertHysteresisPercent: old.defaultAlertHysteresisPercent
    )
}

private func validateLegacyMapping(_ mapping: MappingDTO?, expectedVenue: Venue) throws {
    guard let mapping else { return }
    guard mapping.exchange == expectedVenue.rawValue else {
        throw ValidationFailure.invalid("Mapping exchange does not match its venue property")
    }
    guard Venue(rawValue: mapping.exchange) != nil,
          MappingProvenance(rawValue: mapping.provenance) != nil else {
        throw ValidationFailure.invalid("Invalid mapping enum wire value")
    }
    guard !mapping.productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !mapping.baseAsset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !mapping.quoteAsset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationFailure.invalid("Mapping fields must not be empty")
    }
}

enum SchemaDispatch: Equatable, Sendable {
    case version0
    case version1
    case current
    case unregisteredOlder
    case newer
}

func schemaDispatch(
    version: Int,
    current: Int = currentSchemaVersion,
    registeredVersions: Set<Int> = [0, 1, currentSchemaVersion]
) -> SchemaDispatch {
    if version == current { return .current }
    if version > current { return .newer }
    if version == 0 && registeredVersions.contains(0) { return .version0 }
    if version == 1 && registeredVersions.contains(1) { return .version1 }
    if version > 0 && !registeredVersions.contains(version) { return .unregisteredOlder }
    return .unregisteredOlder
}

@MainActor
final class PersistenceStore {
    let rootDirectory: URL
    let stateURL: URL
    let recoveryBackupURL: URL
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
        self.recoveryBackupURL = rootDirectory.appendingPathComponent("watchlist.recovery-backup.json", isDirectory: false)
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
                state = try Self.domain(from: migrateV1ToV2(migrateV0ToV1(v0)))
                try validatePersistedState(state)
                recoveryProtected = false
                return .migrated(state)
            case .version1:
                let v1 = try decoder.decode(V1StateDTO.self, from: original)
                state = try Self.domain(from: migrateV1ToV2(v1))
                try validatePersistedState(state)
                recoveryProtected = false
                return .migrated(state)
            case .current:
                let v2 = try decoder.decode(V2StateDTO.self, from: original)
                state = try Self.domain(from: v2)
            case .unregisteredOlder:
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

    /// Copies the damaged file aside so a reset does not destroy the only copy.
    ///
    /// An unreadable original is deliberately not an error. One of the four ways
    /// into recovery is that `Data(contentsOf:)` failed, and in exactly that case
    /// this read fails too. Treating that as a reason to abort would leave the
    /// user permanently stuck: the file cannot be read, so it can never be backed
    /// up, so the reset can never run, and the only escape would be deleting the
    /// file by hand in Finder. There is also nothing to protect — bytes that
    /// cannot be read cannot be recovered from a copy either.
    ///
    /// A write failure is different and does propagate. There the original was
    /// read successfully, so it is real, salvageable data, and overwriting it
    /// after failing to save it elsewhere would be the destructive outcome this
    /// backup exists to prevent.
    ///
    /// Returns whether a copy was actually written, so the caller can tell the
    /// user which of the two happened.
    @discardableResult
    func backupRecoveryFile() throws -> Bool {
        guard let original = try? Data(contentsOf: stateURL) else { return false }
        try original.write(to: recoveryBackupURL, options: .atomic)
        return true
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

    static func dto(from state: PersistedState) -> V2StateDTO {
        V2StateDTO(
            schemaVersion: state.schemaVersion,
            items: state.items.map { item in
                V2ItemDTO(
                    id: item.id,
                    coinGeckoID: item.coinGeckoID,
                    symbol: item.symbol,
                    name: item.name,
                    mapping: item.mapping.map(mappingDTO),
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
            alertsEnabled: state.alertsEnabled,
            textSize: state.textSize.rawValue,
            chartRange: state.chartRange.rawValue,
            defaultAlertCooldownSeconds: state.defaultAlertCooldownSeconds,
            defaultAlertHysteresisPercent: decimalString(state.defaultAlertHysteresisPercent)
        )
    }

    static func domain(from dto: V2StateDTO) throws -> PersistedState {
        guard let defaultAlertHysteresisPercent = finiteDecimal(from: dto.defaultAlertHysteresisPercent) else {
            throw ValidationFailure.invalid("Invalid default alert hysteresis wire value")
        }
        return PersistedState(
            schemaVersion: dto.schemaVersion,
            items: try dto.items.map { item in
                WatchItem(
                    id: item.id,
                    coinGeckoID: item.coinGeckoID,
                    symbol: item.symbol,
                    name: item.name,
                    mapping: try item.mapping.map(mapping),
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
            alertsEnabled: dto.alertsEnabled,
            textSize: TextSizePreference(rawValue: dto.textSize) ?? .medium,
            chartRange: ChartRange(rawValue: dto.chartRange) ?? .hours24,
            defaultAlertCooldownSeconds: dto.defaultAlertCooldownSeconds,
            defaultAlertHysteresisPercent: defaultAlertHysteresisPercent
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
