// std/web core contracts — kept un-namespaced (like std/events.xi) so user code
// can `implements WebRequestHandler` / bind `WebTransport` with bare names.
// Imported by std/web.xi; don't import this directly.

// Runtime JSON helpers (called directly to avoid namespace-prefix surprises).
extern "C" {
    mapper   xstd_json_stringify(v: Json) -> String
    producer xstd_json_parse(s: String) -> Json
}

// The request handler contract. `action` is an impure function kind (it mutates
// the response and is not a pure function). Route by overloading `handle` with
// `where` guards on the request — the first matching overload wins; the
// un-guarded overload is the default.
interface WebRequestHandler {
    action handle(req: HttpRequest, res: HttpResponse)
}

// Payload (de)serialization. The default is JSON; bind your own `WebTransport`
// implementor to change the wire format for every res.send / req.parse.
interface WebTransport {
    mapper serialize(payload: Json) -> String
    mapper deserialize(body: String) -> Json
}

class JsonTransport implements WebTransport {
    mapper serialize(payload: Json) -> String { return xstd_json_stringify(payload) }
    mapper deserialize(body: String) -> Json  { return xstd_json_parse(body) }
}
