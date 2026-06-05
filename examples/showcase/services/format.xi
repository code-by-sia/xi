// Two greeting styles — selected by a `where` guard at the use site.
namespace format

interface Formatter {
    mapper format(name: String) -> String
    predicate formal()
}

class Casual implements Formatter {
    deps {}
    mapper format(name: String) -> String { return "hey " + name }
    predicate formal() { return false }
}

class Formal implements Formatter {
    deps {}
    mapper format(name: String) -> String { return "Good day, " + name }
    predicate formal() { return true }
}
