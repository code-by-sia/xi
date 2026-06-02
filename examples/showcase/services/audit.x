// Audit rules — injected as a list (all implementations).
namespace audit

interface Rule { mapper label() -> String }

class AgeRule   implements Rule { deps {} mapper label() -> String { return "age" } }
class EmailRule implements Rule { deps {} mapper label() -> String { return "email" } }
