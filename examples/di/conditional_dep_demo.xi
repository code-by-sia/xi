// Conditional dependency — `dep: I where <cond>`.
//
// When an interface has several implementations, a dependency can pick the right
// one with a guard evaluated over each candidate. Here a Checkout selects the
// first payment gateway that reports itself available in this deployment.
//
//   xc examples/conditional_dep_demo.xi && ./build/conditional_dep_demo
import "std/log.xi"
import "std/convert.xi"

interface PaymentGateway {
    predicate available() -> Bool                 // is this gateway usable here?
    producer   charge(cents: Integer) -> String
}

// Stripe isn't configured in this region, so it reports unavailable.
class StripeGateway implements PaymentGateway {
    deps {}
    predicate available() -> Bool => false
    producer  charge(cents: Integer) -> String => "stripe: charged " + cents
}

// PayPal is ready.
class PayPalGateway implements PaymentGateway {
    deps {}
    predicate available() -> Bool => true
    producer  charge(cents: Integer) -> String => "paypal: charged " + cents
}

interface CheckoutService { producer pay(cents: Integer) -> String }

class Checkout implements CheckoutService {
    // Inject the first PaymentGateway whose `available()` guard holds. The
    // compiler tries each implementor in declaration order; if none match it
    // falls back to the first.
    deps { gateway: PaymentGateway where gateway.available() }
    producer pay(cents: Integer) -> String { return gateway.charge(cents) }
}

module App {}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let checkout = App.resolve(CheckoutService)   // gateway auto-selected by guard
    logger.info(checkout.pay(1999))               // paypal: charged 1999
    return 0
}
