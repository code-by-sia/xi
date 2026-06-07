// Bytes: a raw byte buffer type, distinct from String.
import "std/log.xi"
import "std/bytes.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    let b = bytes.fromString("hello")
    logger.print("length    = " + bytes.length(b))
    logger.print("first byte= " + bytes.at(b, 0))      // 'h' = 104

    let full = bytes.concat(b, bytes.fromString(" world"))
    logger.print("concat    = " + bytes.toString(full))
    logger.print("slice 0:5 = " + bytes.toString(bytes.slice(full, 0, 5)))
    logger.print("empty?    = " + bytes.isEmpty(bytes.empty()))
    return 0
}
