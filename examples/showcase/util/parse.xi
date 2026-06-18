// A function with its own dependency block, returning a Result. It logs (a side
// effect), so it's a `producer`, not a pure `mapper`.
namespace util

producer { logger: logging.Logger } parseAge(s: String) -> model.Age! {
    logger.log("parsing age " + s)
    let n = convert.parseInteger(s)?     // `?` propagates the Err
    if n < 0 or n > 130 { return err("age out of range: " + s) }
    return ok(n)
}
