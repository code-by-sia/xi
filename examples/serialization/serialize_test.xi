// Feature: `obj as Json` (serialize) — the mirror of `json as T` (deserialize).
// Both directions derive the codec from the type's fields, nested included.
import "std/json.xi"

type Address = { city: String, zip: Integer }
type User    = { name: String, age: Integer, addr: Address }

test "serialize a nested compound to a Json tree" {
    let u = User { name: "John Doe", age: 44, addr: Address { city: "Oslo", zip: 100 } }
    let j = u as Json
    assertEq(json.stringify(j), "{\"name\":\"John Doe\",\"age\":44,\"addr\":{\"city\":\"Oslo\",\"zip\":100}}")
}

test "round-trip: obj as Json then json as T" {
    let u    = User { name: "John Doe", age: 44, addr: Address { city: "London", zip: 7 } }
    let back = (u as Json) as User
    assertEq(back.name, "John Doe")
    assertEq(back.age, 44)
    assertEq(back.addr.city, "London")
}
