// A function with its own dependency block, returning a Result.
namespace util

mapper { logger: logging.Logger } parseAge(s: String) -> model.Age! {
    logger.log("parsing age " + s)
    let n = convert.parseInteger(s)?     // `?` propagates the Err
    if n < 0 or n > 130 { return err("age out of range: " + s) }
    return ok(n)
}
