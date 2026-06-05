// Feature showcase: optionals, arrays, match, for loops, modules with DI

type Score    = Number where value >= 0 and value <= 100
type Username = String where value.length > 0

type Player = { name: Username, score: Score }

// --- pure functions ---

predicate isHighScore(p: Player) {
    return p.score >= 90
}

mapper describe(p: Player) -> String {
    if isHighScore(p) {
        return p.name + " [HIGH SCORE: " + p.score + "]"
    } else {
        return p.name + " [score: " + p.score + "]"
    }
}

reducer totalScore(acc: Number, p: Player) -> Number {
    return acc + p.score
}

// --- interfaces and classes ---

interface Leaderboard {
    consumer addPlayer(p: Player)
    mapper topPlayer() -> Player?
    mapper allPlayers() -> Player[]
}

class InMemoryLeaderboard implements Leaderboard {
    deps {}

    consumer addPlayer(p: Player) {
        // simplified: just store one player (would normally append to list)
    }

    mapper topPlayer() -> Player? {
        return none
    }

    mapper allPlayers() -> Player[] {
        return []
    }
}

// --- creators ---

creator makePlayer(name: String, score: Number) -> Player {
    return Player { name: name, score: score }
}

// --- module ---

module Game {
    bind Leaderboard -> InMemoryLeaderboard as singleton
}

// --- entry ---

async entry main(args: String[]) -> Integer {
    let players = [
        makePlayer("Alice", 95),
        makePlayer("Bob",   72),
        makePlayer("Carol", 88)
    ]

    for p in players {
        system.stdout.writeln(describe(p))
    }

    return 0
}
