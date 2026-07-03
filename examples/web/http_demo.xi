// Minimal HTTP/1.1 client (std/http over std/net).
//
// Real requests work against any http:// server:
//     let r = http.get("http://example.com/")
//     if isOk(r) { logger.print(r.value.body) }
//
// This demo exercises the URL and response parsing deterministically (no
// network), so it is reproducible in CI.
import "std/http.xi"
import "std/log.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    let u = http.parseUrl("http://example.com:8080/path?q=1")
    if isOk(u) {
        logger.print("host = " + u.value.host)
        logger.print("port = " + u.value.port)
        logger.print("path = " + u.value.path)
    }

    let https = http.parseUrl("https://secure.example")
    if isErr(https) { logger.print("https -> " + https.err) }

    let raw = "HTTP/1.1 404 Not Found\r\n"
            + "Content-Type: text/plain\r\n"
            + "X-Trace: abc123\r\n"
            + "\r\n"
            + "missing"
    let r = http.parseResponse(raw)
    if isOk(r) {
        let resp = r.value
        logger.print("status      = " + resp.status)
        logger.print("content-type= " + http.header(resp, "Content-Type"))
        logger.print("x-trace     = " + http.header(resp, "x-trace"))
        logger.print("body        = " + resp.body)
    }
    return 0
}
