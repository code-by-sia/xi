// Greeter — auto-wired deps with `where` selection and a list dependency.
namespace greet

interface Greeter { producer greet(u: model.User) -> String }

class FormalGreeter implements Greeter {
    deps {
        logger: logging.Logger
        fmt:    format.Formatter where fmt.formal()
        rules:  audit.Rule[]
    }
    producer greet(u: model.User) -> String {
        logger.log("greeting " + u.name + " (" + rules.len + " audit rules)")
        return fmt.format(u.name)
    }
}
