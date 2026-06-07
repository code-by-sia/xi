// Method overloading with `where` guards.
// At a call site the runtime selects the first overload whose guard holds.

import "std/log.xi"
type ApiResponse = { status: Number, body: String }

mapper mapResponse(res: ApiResponse) -> String where res.status == 200 {
    return "OK: " + res.body
}

mapper mapResponse(res: ApiResponse) -> String where res.status == 404 {
    return "Not Found"
}

mapper mapResponse(res: ApiResponse) -> String where res.status >= 500 {
    return "Server Error (" + res.status + ")"
}

// Unguarded overload acts as the default when no guard matches.
mapper mapResponse(res: ApiResponse) -> String {
    return "Unhandled status: " + res.status
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let ok    = ApiResponse { status: 200, body: "hello" }
    let nf     = ApiResponse { status: 404, body: "" }
    let err    = ApiResponse { status: 503, body: "" }
    let other  = ApiResponse { status: 302, body: "" }

    logger.print(mapResponse(ok))
    logger.print(mapResponse(nf))
    logger.print(mapResponse(err))
    logger.print(mapResponse(other))
    return 0
}
