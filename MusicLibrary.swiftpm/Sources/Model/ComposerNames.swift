import Foundation

/// Puts composer names in one standard form, "Surname, Forenames" (or just the
/// surname when the forenames aren't known), so "Bach", "J.S. Bach",
/// "Bach, JS" and "Johann Sebastian Bach" all become "Bach, Johann Sebastian".
enum ComposerNames {
    private struct Known {
        let surname: String
        let forenames: String
        /// Used when only the surname is given and several composers share it.
        let isDefault: Bool
    }

    // MARK: - Reference data

    /// Well-known composers, chiefly of choral, church and classical music.
    private static let known: [Known] = {
        let rows: [(String, String, Bool)] = [
            ("Bach", "Johann Sebastian", true), ("Bach", "Carl Philipp Emanuel", false),
            ("Bach", "Johann Christian", false), ("Bach", "Wilhelm Friedemann", false),
            ("Handel", "George Frideric", true), ("Haydn", "Joseph", true), ("Haydn", "Michael", false),
            ("Mozart", "Wolfgang Amadeus", true), ("Beethoven", "Ludwig van", true),
            ("Schubert", "Franz", true), ("Mendelssohn", "Felix", true), ("Brahms", "Johannes", true),
            ("Bruckner", "Anton", true), ("Schumann", "Robert", true), ("Liszt", "Franz", true),
            ("Fauré", "Gabriel", true), ("Duruflé", "Maurice", true), ("Poulenc", "Francis", true),
            ("Saint-Saëns", "Camille", true), ("Franck", "César", true), ("Widor", "Charles-Marie", true),
            ("Vierne", "Louis", true), ("Messiaen", "Olivier", true), ("Debussy", "Claude", true),
            ("Ravel", "Maurice", true), ("Gounod", "Charles", true), ("Bizet", "Georges", true),
            ("Berlioz", "Hector", true), ("Charpentier", "Marc-Antoine", true), ("Lully", "Jean-Baptiste", true),
            ("Rameau", "Jean-Philippe", true), ("Elgar", "Edward", true), ("Parry", "Hubert", true),
            ("Stanford", "Charles Villiers", true), ("Vaughan Williams", "Ralph", true), ("Holst", "Gustav", true),
            ("Howells", "Herbert", true), ("Finzi", "Gerald", true), ("Ireland", "John", true),
            ("Britten", "Benjamin", true), ("Tippett", "Michael", true), ("Walton", "William", true),
            ("Rutter", "John", true), ("Chilcott", "Bob", true), ("Goodall", "Howard", true),
            ("Tavener", "John", true), ("Taverner", "John", true), ("Pärt", "Arvo", true),
            ("Lauridsen", "Morten", true), ("Whitacre", "Eric", true), ("Gjeilo", "Ola", true),
            ("Dove", "Jonathan", true), ("MacMillan", "James", true), ("Weir", "Judith", true),
            ("Mathias", "William", true), ("Leighton", "Kenneth", true), ("Harris", "William Henry", true),
            ("Bairstow", "Edward", true), ("Noble", "Thomas Tertius", true), ("Wood", "Charles", true),
            ("Stainer", "John", true), ("Sullivan", "Arthur", true), ("Wesley", "Samuel Sebastian", true),
            ("Wesley", "Samuel", false), ("Walmisley", "Thomas Attwood", true), ("Goss", "John", true),
            ("Ouseley", "Frederick", true), ("Attwood", "Thomas", true), ("Boyce", "William", true),
            ("Greene", "Maurice", true), ("Croft", "William", true), ("Blow", "John", true),
            ("Purcell", "Henry", true), ("Humfrey", "Pelham", true), ("Gibbons", "Orlando", true),
            ("Byrd", "William", true), ("Tallis", "Thomas", true), ("Tomkins", "Thomas", true),
            ("Weelkes", "Thomas", true), ("Morley", "Thomas", true), ("Dowland", "John", true),
            ("Sheppard", "John", true), ("Tye", "Christopher", true), ("Farrant", "Richard", true),
            ("Batten", "Adrian", true), ("Mundy", "William", true), ("White", "Robert", true),
            ("Philips", "Peter", true), ("Dering", "Richard", true), ("Ramsey", "Robert", true),
            ("Palestrina", "Giovanni Pierluigi da", true), ("Victoria", "Tomás Luis de", true),
            ("Lassus", "Orlande de", true), ("Josquin des Prez", "", true), ("Monteverdi", "Claudio", true),
            ("Allegri", "Gregorio", true), ("Gabrieli", "Giovanni", true), ("Gabrieli", "Andrea", false),
            ("Schütz", "Heinrich", true), ("Buxtehude", "Dieterich", true), ("Pachelbel", "Johann", true),
            ("Telemann", "Georg Philipp", true), ("Vivaldi", "Antonio", true),
            ("Pergolesi", "Giovanni Battista", true), ("Scarlatti", "Alessandro", true),
            ("Scarlatti", "Domenico", false), ("Lotti", "Antonio", true), ("Caldara", "Antonio", true),
            ("Arcadelt", "Jacques", true), ("Guerrero", "Francisco", true), ("Morales", "Cristóbal de", true),
            ("Lobo", "Alonso", true), ("Clemens non Papa", "Jacobus", true), ("Hassler", "Hans Leo", true),
            ("Praetorius", "Michael", true), ("Dvořák", "Antonín", true), ("Rachmaninoff", "Sergei", true),
            ("Tchaikovsky", "Pyotr Ilyich", true), ("Bortniansky", "Dmitry", true), ("Chesnokov", "Pavel", true),
            ("Grieg", "Edvard", true), ("Sibelius", "Jean", true), ("Rheinberger", "Josef", true),
            ("Reger", "Max", true), ("Verdi", "Giuseppe", true), ("Rossini", "Gioachino", true),
            ("Puccini", "Giacomo", true), ("Mahler", "Gustav", true), ("Stravinsky", "Igor", true),
            ("Bernstein", "Leonard", true), ("Copland", "Aaron", true), ("Barber", "Samuel", true),
            ("Ives", "Charles", true), ("Willan", "Healey", true), ("Coleridge-Taylor", "Samuel", true),
            ("Moeran", "Ernest John", true), ("Warlock", "Peter", true), ("Grainger", "Percy", true),
            ("Darke", "Harold", true), ("Ley", "Henry", true), ("Shephard", "Richard", true),
            ("Archer", "Malcolm", true), ("Lloyd Webber", "Andrew", true), ("Lloyd Webber", "William", false),
            ("Maxwell Davies", "Peter", true), ("Sterndale Bennett", "William", true), ("Ferguson", "Barry", true),
            ("Sanders", "John", true), ("Moore", "Philip", true), ("Bullock", "Ernest", true),
            ("Thalben-Ball", "George", true), ("Jackson", "Francis", true), ("Rose", "Bernard", true),
            ("Radcliffe", "Philip", true), ("Ayleward", "Richard", true), ("Aston", "Peter", true),
            ("Mendelssohn Hensel", "Fanny", true), ("Hildegard of Bingen", "", true),
        ]
        return rows.map { Known(surname: $0.0, forenames: $0.1, isDefault: $0.2) }
    }()

    /// Surnames made of more than one word (they are never split).
    private static let multiWordSurnames: [[String]] = {
        let names = known.map(\.surname).filter { $0.contains(" ") } + [
            "Mendelssohn Bartholdy", "Saint Saens", "Coleridge Taylor", "Thalben Ball", "Ap Rhys",
        ]
        return names
            .map { fold($0).split(separator: " ").map(String.init) }
            .sorted { $0.count > $1.count }
    }()

    /// Other spellings that should be treated as the same surname.
    private static let aliases: [String: String] = [
        "rachmaninov": "rachmaninoff", "rakhmaninov": "rachmaninoff",
        "lasso": "lassus", "di lasso": "lassus",
        "haendel": "handel", "tchaikowsky": "tchaikovsky", "tschaikowsky": "tchaikovsky",
        "mendelssohn bartholdy": "mendelssohn",
        "des prez": "josquin des prez", "desprez": "josquin des prez", "josquin": "josquin des prez",
        "hildegard": "hildegard of bingen",
        "saint saens": "saint-saens", "coleridge taylor": "coleridge-taylor", "thalben ball": "thalben-ball",
        "von bingen": "hildegard of bingen",
    ]

    /// Words that belong with the surname but are written after the forenames,
    /// e.g. "Beethoven, Ludwig van".
    private static let particles: Set<String> = ["van", "von", "de", "di", "da", "del", "della", "des", "du", "le", "la", "ten", "ter"]

    private static let standardNames: [String: String] = [
        "anonymous": "Anonymous", "anon": "Anonymous", "anon.": "Anonymous",
        "traditional": "Traditional", "trad": "Traditional", "trad.": "Traditional",
        "plainsong": "Plainsong", "plainchant": "Plainsong", "various": "Various",
    ]

    private static let knownBySurname: [String: [Known]] =
        Dictionary(grouping: known, by: { fold($0.surname) })

    // MARK: - API

    /// The standard form of a composer's name.
    static func normalized(_ raw: String) -> String {
        let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return "" }
        if let standard = standardNames[fold(text)] { return standard }
        // Leave combinations ("Bach/Gounod", "Byrd & Tallis") as typed.
        if text.contains("/") || text.contains("&") || fold(text).contains(" and ") { return text }

        var (surname, forenames) = split(text)
        let surnameKey = aliases[fold(surname)] ?? fold(surname)

        if let candidates = knownBySurname[surnameKey], !candidates.isEmpty {
            if let match = bestMatch(candidates, forenames: forenames) {
                return format(match.surname, match.forenames)
            }
            // A composer with this surname we don't know (e.g. another Bach).
            surname = candidates[0].surname
        }
        return format(tidyCase(surname), tidyForenames(forenames))
    }

    /// A key for grouping names that refer to the same person.
    static func groupingKey(_ raw: String) -> String {
        fold(normalized(raw))
    }

    // MARK: - Parsing

    private static func split(_ text: String) -> (surname: String, forenames: String) {
        if let comma = text.firstIndex(of: ",") {
            var surname = String(text[..<comma]).trimmed
            var forenames = String(text[text.index(after: comma)...]).trimmed
            // "Williams, Ralph Vaughan" → "Vaughan Williams, Ralph".
            let foreTokens = forenames.split(separator: " ").map(String.init)
            if let last = foreTokens.last, isMultiWord(fold("\(last) \(surname)")) {
                surname = "\(last) \(surname)"
                forenames = foreTokens.dropLast().joined(separator: " ")
            }
            return (surname, forenames)
        }

        var tokens = text.split(separator: " ").map(String.init)
        if tokens.count == 1 { return (tokens[0], "") }

        // "Bach J.S." (surname first, initials after).
        if let last = tokens.last, looksLikeInitials(last), !looksLikeInitials(tokens[0]) {
            return (tokens.dropLast().joined(separator: " "), last)
        }

        // Known multi-word surnames at the end, e.g. "Ralph Vaughan Williams".
        let folded = tokens.map(fold)
        for surnameTokens in multiWordSurnames where surnameTokens.count <= tokens.count {
            if Array(folded.suffix(surnameTokens.count)) == surnameTokens {
                let surname = tokens.suffix(surnameTokens.count).joined(separator: " ")
                let forenames = tokens.dropLast(surnameTokens.count).joined(separator: " ")
                return (surname, forenames)
            }
        }

        // Otherwise the last word, with particles ("van", "de") moved after the forenames.
        let surname = tokens.removeLast()
        var movedParticles: [String] = []
        while let last = tokens.last, particles.contains(fold(last)), tokens.count > 1 {
            movedParticles.insert(tokens.removeLast(), at: 0)
        }
        // "di Lasso" style aliases need the particle to find the surname.
        if let particle = movedParticles.last, aliases[fold("\(particle) \(surname)")] != nil {
            return ("\(particle) \(surname)", (tokens + movedParticles.dropLast()).joined(separator: " "))
        }
        return (surname, (tokens + movedParticles).joined(separator: " "))
    }

    private static func bestMatch(_ candidates: [Known], forenames: String) -> Known? {
        let given = forenames.trimmed
        if given.isEmpty {
            return candidates.first(where: \.isDefault) ?? candidates.first
        }
        let givenInitials = initials(of: given)
        let givenFolded = fold(given)
        if let exact = candidates.first(where: { fold($0.forenames) == givenFolded || initials(of: $0.forenames) == givenInitials }) {
            return exact
        }
        let partial = candidates.filter {
            let candidate = initials(of: $0.forenames)
            return !givenInitials.isEmpty && candidate.hasPrefix(givenInitials)
        }
        return partial.first(where: \.isDefault) ?? partial.first
    }

    private static func isMultiWord(_ foldedName: String) -> Bool {
        multiWordSurnames.contains { $0.joined(separator: " ") == foldedName }
    }

    // MARK: - Formatting

    private static func format(_ surname: String, _ forenames: String) -> String {
        forenames.isEmpty ? surname : "\(surname), \(forenames)"
    }

    /// "J.S." / "JS" / "Johann Sebastian" → "JS".
    static func initials(of forenames: String) -> String {
        var result = ""
        for word in forenames.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" }) {
            let token = String(word)
            if particles.contains(fold(token)) { continue }
            if token.count <= 3 && token == token.uppercased() && token.allSatisfy(\.isLetter) {
                result += token  // "JS"
            } else if let first = token.first {
                result += String(first).uppercased()
            }
        }
        return result
    }

    private static func looksLikeInitials(_ token: String) -> Bool {
        let letters = token.replacingOccurrences(of: ".", with: "")
        return !letters.isEmpty && letters.count <= 3 && letters == letters.uppercased()
            && letters.allSatisfy(\.isLetter) && (token.contains(".") || letters.count >= 2)
    }

    /// "JS" / "J.S." → "J. S."; otherwise tidies capitalisation.
    private static func tidyForenames(_ forenames: String) -> String {
        let tokens = forenames.split(separator: " ").map(String.init)
        let tidied = tokens.map { token -> String in
            if looksLikeInitials(token) {
                return token.replacingOccurrences(of: ".", with: "").map { "\($0)." }.joined(separator: " ")
            }
            if particles.contains(fold(token)) { return fold(token) }
            return tidyCase(token)
        }
        return tidied.joined(separator: " ")
    }

    /// Capitalises words typed all in lower or upper case; leaves mixed case alone.
    private static func tidyCase(_ text: String) -> String {
        guard text == text.lowercased() || text == text.uppercased() else { return text }
        return text.split(separator: " ").map { word -> String in
            let lower = word.lowercased()
            if particles.contains(lower) { return lower }
            return lower.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
        }.joined(separator: " ")
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmed
    }
}
