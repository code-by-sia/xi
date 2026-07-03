import "std/log.xi"
import "std/math.xi"
import "std/text.xi"
import "std/convert.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.print("sqrt(2)   = " + math.sqrt(2.0))
    logger.print("max(3,7)  = " + math.max(3, 7))
    logger.print("upper     = " + text.toUpper("hello"))
    logger.print("trim      = [" + text.trim("   hi   ") + "]")
    logger.print("repeat    = " + text.repeat("ab", 3))
    logger.print("indexOf   = " + text.indexOf("hello world", "world"))

    let r = convert.parseInteger("44")
    if isOk(r) { logger.print("parsed    = " + r.value) }
    let bad = convert.parseInteger("oops")
    if isErr(bad) { logger.print("error     = " + bad.err) }
    return 0
}
