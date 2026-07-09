// Feature: web controller payload (de)serialization.
//
// A controller replies with `res.send(dto)` and reads a typed body with
// `req.parse(T)`. Both route the payload through the DI-resolved `WebTransport`
// over the compiler's auto-derived JSON codecs (`dto as Json` / `json as T`).
// This test exercises that exact path without standing up a server: bind the
// default `JsonTransport`, then serialize a DTO to the wire and parse it back.
import "std/web.xi"

// The kind of payload a controller sends back (res.send) ...
event  Created = { id: Integer, name: String, active: Bool }
// ... and the kind it accepts in a request body (req.parse).
type   NewUser = { name: String, age: Integer }

module WebPayload { bind WebTransport -> JsonTransport as singleton }

test "serialize a controller response payload (res.send path)" {
    let tx  = WebPayload.resolve(WebTransport)
    let dto = Created { id: 7, name: "John Doe", active: true }
    // res.send(dto) === transport.serialize(dto as Json)
    let wire = tx.serialize(dto as Json)
    assertEq(wire, "{\"id\":7,\"name\":\"John Doe\",\"active\":true}")
}

test "deserialize a request body payload (req.parse path)" {
    let tx   = WebPayload.resolve(WebTransport)
    let body = "{\"name\":\"John Doe\",\"age\":44}"
    // req.parse(NewUser) === transport.deserialize(body) as NewUser
    let u = (tx.deserialize(body)) as NewUser
    assertEq(u.name, "John Doe")
    assertEq(u.age, 44)
}

test "round-trip a payload through the transport" {
    let tx   = WebPayload.resolve(WebTransport)
    let sent = Created { id: 3, name: "Ada", active: false }
    let back = (tx.deserialize(tx.serialize(sent as Json))) as Created
    assertEq(back.id, 3)
    assertEq(back.name, "Ada")
    assertEq(back.active, false)
}
