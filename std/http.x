// std/http — a minimal HTTP/1.1 client over std/net (plain http:// only, no TLS).
//   let r = http.get("http://example.com/")
//   if isOk(r) { system.stdout.writeln(r.value.body) }
namespace http

import "std/net.x"
import "std/text.x"
import "std/convert.x"

type Url      = { host: String, port: Integer, path: String }
// `headers` is the raw header block (CRLF-separated "Key: Value" lines);
// use http.header(resp, name) to look one up.
type Response = { status: Integer, headers: String, body: String }

// Parse "http://host[:port]/path".  https:// is rejected (no TLS support).
mapper parseUrl(u: String) -> Url! {
    let rest = u
    if text.startsWith(rest, "http://") {
        rest = text.substring(rest, 7, text.length(rest))
    } else {
        if text.startsWith(rest, "https://") {
            return err("https is not supported (http only): " + u)
        }
    }
    let slash = text.indexOf(rest, "/")
    let authority = rest
    let path = "/"
    if slash >= 0 {
        authority = text.substring(rest, 0, slash)
        path = text.substring(rest, slash, text.length(rest))
    }
    let host = authority
    let port = 80
    let colon = text.indexOf(authority, ":")
    if colon >= 0 {
        host = text.substring(authority, 0, colon)
        let ps = text.substring(authority, colon + 1, text.length(authority))
        let pr = convert.parseInteger(ps)
        if isErr(pr) { return err("bad port in url: " + u) }
        port = pr.value
    }
    if text.length(host) == 0 { return err("missing host in url: " + u) }
    return ok(Url { host: host, port: port, path: path })
}

// Parse a raw HTTP response into status / headers / body.
mapper parseResponse(raw: String) -> Response! {
    if text.length(raw) == 0 { return err("empty response") }
    let sep = text.indexOf(raw, "\r\n\r\n")
    let head = raw
    let body = ""
    if sep >= 0 {
        head = text.substring(raw, 0, sep)
        body = text.substring(raw, sep + 4, text.length(raw))
    }
    let lines = text.split(head, "\r\n")
    let statusLine = lines.data[0]
    let parts = text.split(statusLine, " ")
    if parts.len < 2 { return err("malformed status line: " + statusLine) }
    let sr = convert.parseInteger(parts.data[1])
    if isErr(sr) { return err("bad status code: " + parts.data[1]) }
    // header block = everything after the first line
    let headers = ""
    let firstLen = text.length(statusLine) + 2     // + CRLF
    if text.length(head) > firstLen {
        headers = text.substring(head, firstLen, text.length(head))
    }
    return ok(Response { status: sr.value, headers: headers, body: body })
}

// Look up a response header by name (case-insensitive); "" if absent.
mapper header(resp: Response, name: String) -> String {
    let lines = text.split(resp.headers, "\r\n")
    let target = text.toLower(name)
    let i = 0
    while i < lines.len {
        let line = lines.data[i]
        let c = text.indexOf(line, ":")
        if c >= 0 {
            let key = text.toLower(text.trim(text.substring(line, 0, c)))
            if key == target {
                return text.trim(text.substring(line, c + 1, text.length(line)))
            }
        }
        i = i + 1
    }
    return ""
}

// Send one request and read the full response (uses Connection: close).
producer request(method: String, url: String, body: String, contentType: String) -> Response! {
    let ur = parseUrl(url)
    if isErr(ur) { return err(ur.err) }
    let u = ur.value

    let cr = net.dial(u.host, u.port)
    if isErr(cr) { return err(cr.err) }
    let c = cr.value

    let req = method + " " + u.path + " HTTP/1.1\r\n"
            + "Host: " + u.host + "\r\n"
            + "User-Agent: x-http/0.1\r\n"
            + "Connection: close\r\n"
    if text.length(body) > 0 {
        req = req + "Content-Type: " + contentType + "\r\n"
                  + "Content-Length: " + text.length(body) + "\r\n"
    }
    req = req + "\r\n" + body

    net.sendText(c, req)

    let raw = ""
    let chunk = net.recvText(c, 8192)
    while text.length(chunk) > 0 {
        raw = raw + chunk
        chunk = net.recvText(c, 8192)
    }
    net.close(c)
    return parseResponse(raw)
}

producer get(url: String) -> Response! { return request("GET", url, "", "") }
producer post(url: String, body: String, contentType: String) -> Response! {
    return request("POST", url, body, contentType)
}
