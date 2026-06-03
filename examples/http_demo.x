// Minimal HTTP/1.1 client (std/http over std/net).
//
// Real requests work against any http:// server:
//     let r = http.get("http://example.com/")
//     if isOk(r) { system.stdout.writeln(r.value.body) }
//
// This demo exercises the URL and response parsing deterministically (no
// network), so it is reproducible in CI.
import "std/http.x"

async entry main(args: String[]) -> Integer {
    let u = http.parseUrl("http://example.com:8080/path?q=1")
    if isOk(u) {
        system.stdout.writeln("host = " + u.value.host)
        system.stdout.writeln("port = " + u.value.port)
        system.stdout.writeln("path = " + u.value.path)
    }

    let https = http.parseUrl("https://secure.example")
    if isErr(https) { system.stdout.writeln("https -> " + https.err) }

    let raw = "HTTP/1.1 404 Not Found\r\n"
            + "Content-Type: text/plain\r\n"
            + "X-Trace: abc123\r\n"
            + "\r\n"
            + "missing"
    let r = http.parseResponse(raw)
    if isOk(r) {
        let resp = r.value
        system.stdout.writeln("status      = " + resp.status)
        system.stdout.writeln("content-type= " + http.header(resp, "Content-Type"))
        system.stdout.writeln("x-trace     = " + http.header(resp, "x-trace"))
        system.stdout.writeln("body        = " + resp.body)
    }
    return 0
}
