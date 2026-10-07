import Foundation
import MySQLClient

/// Read-only view of one stored procedure or function: definition, parameters and metadata.
struct RoutineDetail: Sendable {
    /// nil when the server withholds the body: only the definer, or a user with
    /// SHOW_ROUTINE (or global SELECT), may read it.
    let definition: String?
    let parameters: QueryResult?
    /// Return type; functions only.
    let returns: String?
    let definer: String
    let securityType: String
    let lastAltered: String
    let comment: String

    static func load(connection: MySQLConnection, database: String, routine: RoutineRef) async throws -> RoutineDetail {
        let kind = routine.kind.rawValue
        let info = try await connection.execute([
            "SELECT DEFINER, SECURITY_TYPE, LAST_ALTERED, ROUTINE_COMMENT, DTD_IDENTIFIER",
            " FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = ", .value(database),
            " AND ROUTINE_NAME = ", .value(routine.name), " AND ROUTINE_TYPE = ", .value(kind),
        ]).first?.rows.first
        guard let info else {
            throw Missing(routine: routine)
        }
        // A function's return value is listed as position 0, and its parameters
        // have no mode because they can only be IN.
        let parameters = try await connection.execute([
            "SELECT COALESCE(PARAMETER_MODE, 'IN') AS Modo, PARAMETER_NAME AS Nombre, DTD_IDENTIFIER AS Tipo",
            " FROM information_schema.PARAMETERS WHERE SPECIFIC_SCHEMA = ", .value(database),
            " AND SPECIFIC_NAME = ", .value(routine.name), " AND ROUTINE_TYPE = ", .value(kind),
            " AND ORDINAL_POSITION > 0 ORDER BY ORDINAL_POSITION",
        ]).first
        // Column 2 is "Create Procedure" / "Create Function"; NULL without the privileges above.
        let definition = try await connection.execute([
            .raw("SHOW CREATE \(kind) "), .identifier(database), ".", .identifier(routine.name),
        ]).first?.rows.first?[2]

        return RoutineDetail(
            definition: definition,
            parameters: parameters,
            returns: routine.kind == .function ? info[4] : nil,
            definer: info[0] ?? "",
            securityType: info[1] ?? "",
            lastAltered: info[2] ?? "",
            comment: info[3] ?? ""
        )
    }

    /// Dropped since the sidebar was loaded.
    struct Missing: LocalizedError {
        let routine: RoutineRef
        var errorDescription: String? {
            let noun = routine.kind == .procedure ? "El procedimiento" : "La función"
            return "\(noun) \(routine.name) ya no existe. Recarga la lista."
        }
    }
}
