// Type aliases (incl. plural array aliases) and `empty` (zero values).
import "std/log.xi"
type Person = { name: String, age: Number }
type People = Person[]               // a readable alias for Person[]
type Name   = String                 // plain alias

mapper headcount(p: People) -> Integer { return p.len }

type Team = { lead: Person, members: People }

async entry (logger: Logger) main(args: String[]) -> Integer {
    let team: People = [
        Person { name: "Ada", age: 36 },
        Person { name: "Bo",  age: 29 }
    ]
    logger.print("headcount = " + headcount(team))

    // `empty T` — the zero value of any type.
    let noone = empty Person
    logger.print("empty Person age = " + noone.age)        // 0

    let nobody = empty People
    logger.print("empty People len = " + nobody.len)       // 0

    let blank = empty Team
    logger.print("empty Team members = " + blank.members.len) // 0

    let label: Name = "shipping"
    logger.print("label = " + label)
    return 0
}
