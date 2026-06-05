// Domain types: refined types, a compound type, a creator, a predicate.
namespace model

type Age   = Number where value >= 0 and value <= 130
type Name  = String where value.length > 0
type Email = String where value matches /^[^@\s]+@[^@\s]+\.[^@\s]+$/

type User = { name: Name, age: Age, email: Email }

creator makeUser(name: String, age: Number, email: String) -> User {
    return User { name: name, age: age, email: email }
}

predicate isAdult(u: User) { return u.age >= 18 }
