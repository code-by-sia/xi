// Demonstrate refined types, constraints, and creators

type Age        = Number where value >= 0 and value <= 130
type PositiveInt = Number where value > 0
type Email      = String where value matches /^[^@\s]+@[^@\s]+\.[^@\s]+$/
type NonEmpty   = String where value.length > 0

type Person = { name: NonEmpty, age: Age, email: Email }

creator makePerson(name: String, age: Number, email: String) -> Person {
    return Person {
        name: name,
        age: age,
        email: email
    }
}

predicate isMinor(p: Person) {
    return p.age < 18
}

mapper describe(p: Person) -> String {
    return p.name + " (age " + p.age + ")"
}

async entry main(args: String[]) -> Integer {
    let alice = makePerson("Alice", 30, "alice@example.com")
    let bob   = makePerson("Bob",   15, "bob@example.com")

    system.stdout.writeln(describe(alice))
    system.stdout.writeln(describe(bob))

    if isMinor(bob) {
        system.stdout.writeln(bob.name + " is a minor")
    }

    return 0
}
