// where-guarded overloading over a domain type.
namespace rules

mapper classify(u: model.User) -> String where u.age < 18 { return "minor" }
mapper classify(u: model.User) -> String                  { return "adult" }
