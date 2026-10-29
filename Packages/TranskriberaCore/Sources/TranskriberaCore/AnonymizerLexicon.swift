import Foundation

/// Ordlistor och mönster som namnigenkänningen i `Anonymizer` använder. Alla ord är gemener.
enum Lexicon {
    /// Ett ord som börjar med stor bokstav, t.ex. "Anna", "Anna-Karin", "O'Brien".
    static let capitalizedWord = TextPattern(#"(?<![\p{L}\p{N}])\p{Lu}[\p{L}\p{M}'’]*(?:-\p{L}[\p{L}\p{M}'’]*)*"#)

    /// Ett ord som börjar med liten bokstav.
    static let lowercaseWord = TextPattern(#"(?<![\p{L}\p{N}])\p{Ll}[\p{L}\p{M}'’]*(?:-\p{L}[\p{L}\p{M}'’]*)*"#)

    /// Ord efter ett namn som gör det till en organisation, t.ex. "Volvo AB", "Lunds universitet".
    static let organizationFollower = TextPattern(
        #" +(?:ab|kommun|kommuns|universitet|universitetet|högskola|högskolan|sjukhus|sjukhuset|landsting|förening|föreningen|skola|skolan|gymnasium|gymnasiet|vårdcentral|vårdcentralen|församling|stift)(?![\p{L}])"#,
        caseInsensitive: true
    )

    /// Slår också upp genitivformen ("Annas" → "anna").
    static func contains(_ set: Set<String>, _ key: String) -> Bool {
        if set.contains(key) { return true }
        guard key.count > 3, key.hasSuffix("s") else { return false }
        return set.contains(String(key.dropLast()))
    }

    static func hasSuffix(_ key: String, _ suffixes: [String]) -> Bool {
        suffixes.contains { key.count > $0.count + 1 && key.hasSuffix($0) }
    }

    static let nameParticles: Set<String> = ["von", "af", "van", "de", "der", "di", "da", "du", "del", "la", "le"]

    /// Vanliga ord som kan stå med stor bokstav utan att vara namn.
    static let stopwords: Set<String> = [
        "jag", "ja", "nej", "jo", "okej", "ok", "hej", "hejsan", "tack", "och", "men", "så", "det", "den", "de", "dem",
        "du", "dig", "vi", "oss", "ni", "er", "han", "hon", "hen", "man", "en", "ett", "i", "är", "att", "som", "för",
        "på", "med", "om", "eller", "när", "var", "vad", "hur", "varför", "här", "där", "nu", "sen", "också", "bara",
        "alltså", "liksom", "typ", "precis", "absolut", "visst", "kanske", "inte", "ingen", "inget", "alla", "mm",
        "mhm", "aha", "oj", "åh", "hmm", "eh", "äh", "nä", "nja", "ah", "herregud", "gud", "fan", "jaha", "jaså",
        "the", "and", "you", "we", "he", "she", "it", "they", "yes", "no", "okay", "hi", "hello", "thanks",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december", "english", "swedish"
    ]

    static let firstNames: Set<String> = [
        // Kvinnor
        "anna", "eva", "maria", "karin", "sara", "lena", "kristina", "emma", "kerstin", "elin", "ingrid", "marie",
        "malin", "jenny", "hanna", "linda", "annika", "susanne", "johanna", "birgitta", "elisabeth", "inger",
        "ulla", "camilla", "sofia", "helena", "sofie", "ida", "julia", "louise", "frida", "therese", "cecilia",
        "monica", "ebba", "alice", "maja", "elsa", "astrid", "wilma", "olivia", "ella", "agnes", "freja", "saga",
        "klara", "lisa", "matilda", "amanda", "josefin", "jessica", "caroline", "lina", "emelie", "petra",
        "åsa", "anneli", "gunilla", "margareta", "birgit", "agneta", "ulrika", "anette", "pia", "mia", "katarina",
        "charlotte", "madeleine", "veronica", "ylva", "tove", "nora", "selma", "stina", "vera", "elvira",
        "anna-karin", "ann-sofie", "ann", "britt", "gun", "siv", "eva-lena", "fatima", "amina", "leila",
        // Män
        "lars", "mikael", "anders", "johan", "per", "erik", "karl", "peter", "jan", "thomas", "daniel", "fredrik",
        "hans", "andreas", "stefan", "mats", "marcus", "magnus", "mattias", "jonas", "niklas", "nicklas", "bengt",
        "martin", "björn", "henrik", "patrik", "alexander", "christer", "oskar", "oscar", "william", "liam",
        "noah", "hugo", "lucas", "adam", "elias", "axel", "filip", "viktor", "victor", "emil", "isak", "olle",
        "nils", "gustav", "gustaf", "sven", "ola", "kalle", "pelle", "janne", "lasse", "micke", "jonathan",
        "simon", "robin", "sebastian", "tobias", "joakim", "rickard", "richard", "kristoffer", "christoffer",
        "jesper", "linus", "albin", "anton", "ludvig", "leo", "arvid", "melvin", "theo", "vincent", "max",
        "ali", "mohammed", "mohammad", "ahmed", "omar", "hassan", "ibrahim", "lars-erik", "per-olof", "jan-erik",
        "göran", "leif", "kent", "roger", "ulf", "tommy", "bo", "åke", "rolf", "kjell", "torbjörn", "håkan",
        "gunnar", "ingvar", "sten", "stig", "rune", "arne", "tomas", "jakob", "jacob", "david", "samuel",
        "rasmus", "dennis", "jimmy", "johnny", "robert", "roland", "lennart", "kenneth", "conny", "glenn",
        "sixten", "elof", "algot", "edvin", "alvin", "casper", "kasper", "colin", "milo", "otto", "harry",
        "charlie", "frank", "julius", "malte", "melker", "loke", "valter", "walter", "wilhelm", "vilhelm",
        "ivar", "einar", "folke", "tage", "sune", "evert", "allan", "ove", "ronny", "benny", "tony", "mikko",
        "niclas", "nikolas", "nicholas", "mikkel", "jens", "lukas", "jonatan", "felix", "oliver", "isac",
        "joel", "joy", "kevin", "andré", "andre", "carl", "claes", "klas", "christian", "kristian", "anders-petter",
        "mohamed", "yusuf", "mustafa", "abdi", "karim", "amir", "reza",
        // Fler kvinnonamn
        "lovisa", "ellen", "tilda", "tindra", "molly", "nellie", "ronja", "signe", "edith", "ester",
        "greta", "iris", "lea", "leah", "lova", "luna", "meja", "minna", "nova",
        "stella", "thea", "tyra", "vilma", "hedvig", "sigrid", "märta", "ingegerd", "barbro", "gunnel",
        "solveig", "yvonne", "marianne", "lotta", "jeanette", "sandra", "rebecka", "rebecca", "emilia",
        "isabelle", "isabella", "natalie", "nathalie", "michaela", "mikaela", "angelica", "angelika",
        "erika", "jennifer", "carina", "katja", "paulina", "pauline", "sanna", "sara-lena", "therése",
        "zara", "yasmin", "sofi", "elina", "kajsa", "ebba-lotta", "ann-christin", "ann-marie"
    ]

    static let places: Set<String> = [
        "sverige", "norge", "danmark", "finland", "island", "tyskland", "frankrike", "spanien", "italien",
        "england", "storbritannien", "skottland", "irland", "nederländerna", "holland", "belgien", "schweiz",
        "österrike", "polen", "ukraina", "ryssland", "estland", "lettland", "litauen", "grekland", "turkiet",
        "portugal", "usa", "amerika", "kanada", "mexiko", "brasilien", "kina", "japan", "indien", "thailand",
        "australien", "europa", "afrika", "asien", "irak", "iran", "syrien", "somalia", "eritrea", "afghanistan",
        "stockholm", "göteborg", "malmö", "uppsala", "västerås", "örebro", "linköping", "helsingborg", "jönköping",
        "norrköping", "lund", "umeå", "gävle", "borås", "södertälje", "eskilstuna", "halmstad", "växjö",
        "karlstad", "sundsvall", "östersund", "trollhättan", "luleå", "kalmar", "kristianstad", "skövde", "falun",
        "karlskrona", "visby", "kiruna", "skellefteå", "uddevalla", "varberg", "nyköping", "örnsköldsvik",
        "gotland", "öland", "skåne", "norrland", "värmland", "dalarna", "småland", "halland", "lappland",
        "jämtland", "blekinge", "uppland", "västergötland", "östergötland", "norrbotten", "västerbotten",
        "solna", "sundbyberg", "nacka", "täby", "huddinge", "botkyrka", "järfälla", "lidingö", "danderyd",
        "södermalm", "kungsholmen", "östermalm", "vasastan", "norrmalm", "gamla stan", "oslo", "köpenhamn",
        "helsingfors", "berlin", "london", "paris", "new york"
    ]

    static let organizationWords: Set<String> = ["ab", "region", "kommun", "aktiebolag", "inc", "ltd", "gmbh", "hb", "kb"]

    static let organizationSuffixes = [
        "bolaget", "banken", "verket", "myndigheten", "kassan", "förmedlingen", "nämnden", "styrelsen", "partiet",
        "sjukhuset", "universitetet", "högskolan", "institutet", "förbundet", "akademien", "fonden", "kliniken",
        "gruppen", "koncernen", "byrån", "inspektionen"
    ]

    static let streetSuffixes = [
        "gatan", "vägen", "gränd", "gränden", "torget", "backen", "stigen", "allén", "leden", "platsen",
        "esplanaden", "kajen", "stranden"
    ]

    static let surnameSuffixes = [
        "sson", "son", "berg", "ström", "lund", "qvist", "kvist", "gren", "dahl", "holm", "ander", "stedt",
        "feldt", "blad", "borg", "lind", "ling", "ius", "mark", "bäck", "sjö", "strand"
    ]

    static let placeSuffixes = [
        "köping", "stad", "hamn", "sund", "vik", "torp", "fors", "ryd", "hult", "måla", "näs", "ås", "landet"
    ]
}
