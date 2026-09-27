import Foundation

/// Ссылки-приглашения без читаемых идентификаторов: `https://cnnect.ru/l/v1/<base64url(путь+query)>`.
///
/// Внутри — обычный путь веб-клиента (`/invite/<roomId>`, `/post-feed-invite/<id>`,
/// `/share/meet/<code>`), base64url без паддинга. Это не шифрование; версия — отдельный сегмент,
/// чтобы позже добавить `v2` (шифрование/подпись, T45). Та же схема — `internal/shareLink.ts`
/// в connect-ui и `ru.aleksandr.connect.link.ShareLinks` на бэкенде.
public enum ShareLinks {
    public static let prefix = "/l/"
    public static let version = "v1"
    public static let maxTargetLength = 2048

    private static let payloadAlphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// `/invite/<id>` → `/l/v1/<base64url>`; `nil`, если это не путь приложения.
    public static func encodePath(_ target: String) -> String? {
        guard isValidTarget(target) else { return nil }
        let base64 = Data(target.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + version + "/" + base64
    }

    /// Полная ссылка для «Скопировать»/«Поделиться».
    public static func url(origin: URL, target: String) -> URL? {
        guard let path = encodePath(target) else { return nil }
        var base = origin.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    /// Ссылка нового формата (любой версии)?
    public static func isShareLink(_ input: String) -> Bool {
        path(of: input)?.hasPrefix(prefix) == true
    }

    /// Исходный путь с query из ссылки или пути `/l/v1/...`; `nil` — не она, чужая версия или мусор.
    public static func decode(_ input: String) -> String? {
        guard let path = path(of: input), path.hasPrefix(prefix + version + "/") else { return nil }
        var payload = String(path.dropFirst(prefix.count + version.count + 1))
        if payload.hasSuffix("/") { payload.removeLast() }
        guard (2...2800).contains(payload.count), payload.unicodeScalars.allSatisfy(payloadAlphabet.contains),
              payload.count % 4 != 1 else { return nil }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let target = String(data: data, encoding: .utf8),
              isValidTarget(target) else { return nil }
        return target
    }

    /// Только путь приложения: один «/» в начале, без «\», «#», управляющих символов и вложенной `/l/`.
    public static func isValidTarget(_ target: String) -> Bool {
        !target.isEmpty && target.utf16.count <= maxTargetLength
            && target.hasPrefix("/") && !target.hasPrefix("//") && !target.hasPrefix(prefix)
            && !target.contains("\\") && !target.contains("#")
            && !target.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }

    private static func path(of input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return String(trimmed.prefix { $0 != "?" && $0 != "#" })
        }
        guard let components = URLComponents(string: trimmed), components.scheme != nil else { return nil }
        return components.percentEncodedPath
    }
}
