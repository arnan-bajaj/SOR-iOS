import Foundation

/// One dated occurrence on the team calendar.
/// The `id` must match the web app's (mod-calendar `expand`) and the bot's (lib/calendar.mjs): signups,
/// attendance and settings/slackSignups are keyed by it.
struct CalEvent: Identifiable, Hashable {
    let id: String
    let uid: String
    let title: String
    let place: String
    let link: String
    let service: String
    let code: String
    let mode: String // "in-person" | "online" | "hybrid" | ""
    let description: String
    let allDay: Bool
    let start: Double // ms
    let end: Double // ms
    let dayKey: String

    var startDate: Date { Date(timeIntervalSince1970: start / 1000) }
    var endDate: Date { Date(timeIntervalSince1970: end / 1000) }

    private static let competitionRE = try! NSRegularExpression(pattern: #"throwdown|classic|showdown|regional|district|championship|\bchamps\b|competition|scrimmage|invitational|qualifier|\bweek 0\b"#, options: .caseInsensitive)
    var isCompetition: Bool { Self.competitionRE.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil }
    var isNotCompeting: Bool { title.range(of: "not competing", options: .caseInsensitive) != nil }
    var isHangar: Bool { title.range(of: "hangar", options: .caseInsensitive) != nil }
    /// trackFromTitle in mod-state
    var track: String {
        if title.range(of: "build committee", options: .caseInsensitive) != nil { return "build" }
        if title.range(of: #"board (meeting|mtg)"#, options: [.caseInsensitive, .regularExpression]) != nil { return "board" }
        if title.range(of: "operations", options: .caseInsensitive) != nil { return "ops" }
        return ""
    }

    /// "6:00 – 9:00 PM", "All day", "Mar 6 – Mar 8"
    var whenLabel: String {
        if allDay {
            let days = Int(((end - start) / TeamCalendar.day).rounded())
            if days <= 1 { return "All day" }
            let f = Date.FormatStyle().month(.abbreviated).day()
            var utc = f; utc.timeZone = TimeZone(identifier: "UTC")!
            return "\(startDate.formatted(utc)) – \(Date(timeIntervalSince1970: (end - TeamCalendar.day) / 1000).formatted(utc))"
        }
        let f = Date.IntervalFormatStyle(date: .omitted, time: .shortened)
        return (startDate..<max(endDate, startDate)).formatted(f)
    }

    /// "Five Rivers Aviation, 700 Terminal Cir, Livermore, CA 94551" → "Five Rivers Aviation, Livermore"
    var shortPlace: String {
        let parts = place.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count < 3 { return place }
        return parts[0].first?.isNumber == true ? "\(parts[0]), \(parts[1])" : "\(parts[0]), \(parts[2])"
    }
}

/// A Swift port of the web app's ICS reader (mod-calendar): parse, then expand repeating events.
/// The live app reads the ICS text the bot keeps in settings/calendar.
enum TeamCalendar {
    static let day: Double = 86_400_000

    struct Prop { let name: String; let params: [String: String]; let value: String }
    typealias RawEvent = [String: [Prop]]
    struct Parsed { var tz = "America/Los_Angeles"; var name = ""; var events: [RawEvent] = [] }

    /// Every occurrence from 90 days back to 240 ahead, like the web app keeps.
    static func events(fromICS ics: String, now: Date = Date()) -> [CalEvent] {
        let ms = now.timeIntervalSince1970 * 1000
        return expand(parse(ics), from: ms - 90 * day, to: ms + 240 * day)
    }

    // MARK: Parsing

    static func parseLine(_ line: Substring) -> Prop? {
        var inQuotes = false
        var colon: Substring.Index?
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() } else if c == ":" && !inQuotes { colon = i; break }
            i = line.index(after: i)
        }
        guard let colon else { return nil }
        let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false)
        var params: [String: String] = [:]
        for kv in head.dropFirst() {
            guard let eq = kv.firstIndex(of: "="), eq > kv.startIndex else { continue }
            var v = String(kv[kv.index(after: eq)...])
            if v.hasPrefix("\"") { v.removeFirst() }
            if v.hasSuffix("\"") { v.removeLast() }
            params[kv[..<eq].uppercased()] = v
        }
        return Prop(name: (head.first.map(String.init) ?? "").uppercased(), params: params, value: String(line[line.index(after: colon)...]))
    }

    static func unescape(_ v: String) -> String {
        var out = ""
        var it = v.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n", "N": out.append("\n")
                case "\\", ";", ",": out.append(n)
                default: out.append(c); out.append(n)
                }
            } else { out.append(c) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ text: String) -> Parsed {
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var cal = Parsed()
        var stack: [String] = []
        var ev: RawEvent?
        for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let p = parseLine(line) else { continue }
            if p.name == "BEGIN" {
                stack.append(p.value)
                if p.value == "VEVENT" { ev = [:] }
            } else if p.name == "END" {
                if stack.popLast() == "VEVENT", let e = ev { cal.events.append(e); ev = nil }
            } else if stack.last == "VEVENT", ev != nil {
                ev![p.name, default: []].append(p)
            } else if stack.last == "VCALENDAR" {
                if p.name == "X-WR-TIMEZONE" { cal.tz = p.value.trimmingCharacters(in: .whitespaces) }
                if p.name == "X-WR-CALNAME" { cal.name = unescape(p.value) }
            }
        }
        return cal
    }

    static func prop(_ ev: RawEvent, _ name: String) -> String { ev[name]?.first?.value ?? "" }

    // MARK: Dates

    struct PDate { let allDay: Bool; let tz: String; let parts: [Int]; let ms: Double }

    static func instant(_ p: [Int], tz: String) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "America/Los_Angeles")!
        let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: p[3], minute: p[4], second: p[5])) ?? .distantPast
        return d.timeIntervalSince1970 * 1000
    }
    static func utc(_ y: Int, _ m: Int, _ d: Int) -> Double { instant([y, m, d, 0, 0, 0], tz: "UTC") }

    static func parseDate(_ p: Prop?, calTz: String) -> PDate? {
        guard let p else { return nil }
        let v = Array(p.value.trimmingCharacters(in: .whitespaces))
        func n(_ a: Int, _ b: Int) -> Int? { Int(String(v[a..<b])) }
        guard v.count >= 8, let y = n(0, 4), let mo = n(4, 6), let d = n(6, 8) else { return nil }
        if p.params["VALUE"] == "DATE" || v.count == 8 {
            return PDate(allDay: true, tz: "UTC", parts: [y, mo, d, 0, 0, 0], ms: utc(y, mo, d))
        }
        guard v.count >= 15, v[8] == "T", let h = n(9, 11), let mi = n(11, 13), let s = n(13, 15) else { return nil }
        let parts = [y, mo, d, h, mi, s]
        if v.count == 16 && v[15] == "Z" { return PDate(allDay: false, tz: "UTC", parts: parts, ms: instant(parts, tz: "UTC")) }
        let tz = p.params["TZID"] ?? calTz
        return PDate(allDay: false, tz: tz, parts: parts, ms: instant(parts, tz: tz))
    }

    // MARK: Repeating events

    static let dow = ["SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6]

    static func utcWeekday(_ dayMs: Double) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.component(.weekday, from: Date(timeIntervalSince1970: dayMs / 1000)) - 1
    }
    static func utcParts(_ dayMs: Double) -> (Int, Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: dayMs / 1000))
        return (c.year!, c.month!, c.day!)
    }
    static func daysIn(_ y: Int, _ m: Int) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: y, month: m, day: 1))!
        return cal.range(of: .day, in: .month, for: d)!.count
    }

    /// Occurrence start instants. Steps in wall-clock days, so a 6 pm meeting stays at 6 pm across DST.
    static func occurrences(_ start: PDate, rule: [String: String], from: Double, to: Double) -> [Double] {
        let y = start.parts[0], mo = start.parts[1], d = start.parts[2], h = start.parts[3], mi = start.parts[4], s = start.parts[5]
        let baseDay = utc(y, mo, d)
        let until = rule["UNTIL"].flatMap { parseDate(Prop(name: "", params: [:], value: $0), calTz: "UTC")?.ms } ?? .infinity
        let count = rule["COUNT"].flatMap { Int($0) } ?? Int.max
        let interval = max(1, Int(rule["INTERVAL"] ?? "") ?? 1)
        func at(_ day: Double) -> Double {
            if start.allDay { return day }
            let (yy, mm, dd) = utcParts(day)
            return instant([yy, mm, dd, h, mi, s], tz: start.tz)
        }
        let freq = rule["FREQ"] ?? ""
        let period: Double = freq == "WEEKLY" ? 7 : freq == "DAILY" ? 1 : 0
        var i = period > 0 && count == Int.max ? max(0, Int(((from - baseDay) / (period * Double(interval) * day)).rounded(.down)) - 1) : 0
        var n = 0
        var out: [Double] = []
        for _ in 0..<3000 {
            defer { i += 1 }
            var days: [Double]
            switch freq {
            case "WEEKLY":
                let weekStart = baseDay - Double(utcWeekday(baseDay)) * day + Double(i * interval * 7) * day
                let byday = rule["BYDAY"].map { $0.split(separator: ",").compactMap { dow[String($0.suffix(2))] } } ?? [utcWeekday(baseDay)]
                days = byday.sorted().map { weekStart + Double($0) * day }
            case "DAILY":
                days = [baseDay + Double(i * interval) * day]
            case "MONTHLY", "YEARLY":
                let (yy, mm): (Int, Int)
                if freq == "MONTHLY" {
                    let total = (mo - 1) + i * interval
                    (yy, mm) = (y + total / 12, total % 12 + 1)
                } else { (yy, mm) = (y + i * interval, mo) }
                if d > daysIn(yy, mm) { continue } // e.g. no Feb 30
                days = [utc(yy, mm, d)]
            default:
                return [start.ms] // unsupported rule: just the first one
            }
            for dd in days where dd >= baseDay {
                let ms = at(dd)
                if ms > until || n >= count || ms > to { return out }
                n += 1
                out.append(ms)
            }
        }
        return out
    }

    // MARK: Where

    static let urlRE = try! NSRegularExpression(pattern: #"https?://[^\s<>"')]+"#, options: .caseInsensitive)
    static let videoRE = try! NSRegularExpression(pattern: #"zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|discord\.(gg|com)"#, options: .caseInsensitive)

    static func urls(_ s: String) -> [String] {
        urlRE.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }
    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    static func serviceName(_ link: String) -> String {
        let l = link.lowercased()
        if l.contains("zoom.us") { return "Zoom" }
        if l.contains("meet.google.com") { return "Google Meet" }
        if l.contains("teams.microsoft.com") || l.contains("teams.live.com") { return "Microsoft Teams" }
        if l.contains("webex.com") { return "Webex" }
        if l.contains("discord.") { return "Discord" }
        return "Meeting link"
    }

    static func meetingCode(_ link: String) -> String {
        if let r = link.range(of: #"zoom\.us/j/(\d{9,11})"#, options: [.regularExpression, .caseInsensitive]) {
            let n = Array(link[r].split(separator: "/").last ?? "")
            let s = { (a: Int, b: Int) in String(n[a..<min(b, n.count)]) }
            return n.count == 11 ? "Meeting ID \(s(0, 3)) \(s(3, 7)) \(s(7, 11))" : "Meeting ID \(s(0, 3)) \(s(3, 6)) \(s(6, n.count))"
        }
        if let r = link.range(of: #"meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#, options: [.regularExpression, .caseInsensitive]) {
            return String(link[r].split(separator: "/").last ?? "")
        }
        return ""
    }

    // MARK: Expand

    static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func expand(_ cal: Parsed, from: Double, to: Double) -> [CalEvent] {
        // one-off edits of a repeating event (RECURRENCE-ID) replace that date of the series
        var edited: [String: Set<Double>] = [:]
        for ev in cal.events {
            guard let rid = parseDate(ev["RECURRENCE-ID"]?.first, calTz: cal.tz) else { continue }
            edited[prop(ev, "UID"), default: []].insert(rid.ms)
        }

        var out: [CalEvent] = []
        for ev in cal.events {
            if prop(ev, "STATUS").uppercased() == "CANCELLED" { continue }
            guard let start = parseDate(ev["DTSTART"]?.first, calTz: cal.tz) else { continue }
            let end = parseDate(ev["DTEND"]?.first, calTz: cal.tz)
            let duration = end.map { max(0, $0.ms - start.ms) } ?? (start.allDay ? day : 3_600_000)
            let uidRaw = prop(ev, "UID")
            let uid = uidRaw.isEmpty ? "\(prop(ev, "SUMMARY"))-\(Int64(start.ms))" : uidRaw
            let uidKey = String(String(uid.split(separator: "@", omittingEmptySubsequences: false).first ?? "")
                .unicodeScalars.filter { ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
                .map(Character.init).prefix(32))

            let title = { let t = unescape(prop(ev, "SUMMARY")); return t.isEmpty ? "Untitled event" : t }()
            let location = unescape(prop(ev, "LOCATION"))
            let description = unescape(prop(ev, "DESCRIPTION"))
            let found = urls(location) + urls(description) + [prop(ev, "URL")].filter { !$0.isEmpty }
            let link = found.first { matches(videoRE, $0) } ?? urls(location).first ?? ""
            var place = urlRE.stringByReplacingMatches(in: location, range: NSRange(location.startIndex..., in: location), withTemplate: "")
            place = place.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,;|–-"))
            if let r = place.range(of: #",\s*USA$"#, options: [.regularExpression, .caseInsensitive]) { place.removeSubrange(r) }
            let mode = !link.isEmpty && !place.isEmpty ? "hybrid" : !link.isEmpty ? "online" : !place.isEmpty ? "in-person" : ""

            func add(_ ms: Double, _ keyMs: Double) {
                if ms + duration < from || ms > to { return }
                let iso = isoFmt.string(from: Date(timeIntervalSince1970: keyMs / 1000)).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
                let key = String(iso.prefix(start.allDay ? 8 : 13))
                let dayKey: String
                if start.allDay { let (yy, mm, dd) = utcParts(ms); dayKey = String(format: "%04d-%02d-%02d", yy, mm, dd) } else { dayKey = Day.iso(Date(timeIntervalSince1970: ms / 1000)) }
                out.append(CalEvent(id: "cal-\(uidKey)-\(key)", uid: uid, title: title, place: place, link: link,
                                    service: link.isEmpty ? "" : serviceName(link), code: link.isEmpty ? "" : meetingCode(link),
                                    mode: mode, description: description, allDay: start.allDay, start: ms, end: ms + duration, dayKey: dayKey))
            }

            if let rid = parseDate(ev["RECURRENCE-ID"]?.first, calTz: cal.tz) { add(start.ms, rid.ms); continue }
            let rrule = prop(ev, "RRULE")
            if rrule.isEmpty { add(start.ms, start.ms); continue }

            var skip = edited[uid] ?? []
            for p in ev["EXDATE"] ?? [] {
                for v in p.value.split(separator: ",") {
                    if let x = parseDate(Prop(name: "", params: p.params, value: String(v)), calTz: cal.tz) { skip.insert(x.ms) }
                }
            }
            var rule: [String: String] = [:]
            for kv in rrule.split(separator: ";") {
                let pair = kv.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { rule[pair[0].uppercased()] = String(pair[1]) }
            }
            for ms in occurrences(start, rule: rule, from: from, to: to) where !skip.contains(ms) { add(ms, ms) }
        }
        return out.sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
    }
}
