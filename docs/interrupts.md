# Interrupts (resumable conditions)

> **Status: Implemented** — `skip` + `recover`, for top-level functions,
> `entry`, and class methods. `retry`, value-producing signals, and *checking*
> of the `interrupts T` annotation (it is currently parsed but not enforced)
> remain future work (see Limitations). Runnable: `examples/interrupts/interrupt_demo.xi`.

## Summary

`interrupt` introduces **resumable conditions** to Xi. When a function `signal`s
an interrupt, that function is **suspended at the signal site** — it does *not*
unwind. A handler in an enclosing `try`/`catch` runs while the suspended frame is
still alive and **decides** what happens next:

- **`recover`** — the suspended function resumes: it runs the inline `recover { }`
  block at the signal site and continues from there.
- **`skip`** — the suspended function is abandoned; control returns after the
  `try`.

It is **checked**: a function that may signal declares `interrupts T`, and the
compiler verifies that callers either handle or re-declare it.

This is the Common Lisp condition/restart model (also seen in Smalltalk's
resumable exceptions and algebraic effects), adapted to Xi's C backend and its
pure/impure function-kind system.

## Execution model (the key idea)

> The running method that raises an interrupt **gets interrupted**, and only
> continues once the interruption is **managed at an upper stack frame**.

```
foo() running ──signal T──▶ foo SUSPENDED here (frame kept alive)
                                  │
                                  ▼
                  handler search up the stack → matching catch
                                  │
                  catch body runs (no unwinding yet), decides:
                     ├─ recover ─▶ run foo's recover{} block, foo CONTINUES
                     └─ skip ────▶ unwind to the try, foo ABANDONED
```

Contrast with Xi's existing `Result` and with classic exceptions:

| Mechanism | Use | Stack behaviour |
|-----------|-----|-----------------|
| `Result` (`T!`, `?`) | expected, local errors handled as values | none; caller inspects |
| **Interrupt** | recoverable conditions; an outer policy decides | handler runs with the signalling frame intact, then resumes or abandons |
| (classic exceptions) | — | would unwind *before* the handler; not in Xi |

## Syntax

```x
// 1. Declare an interrupt type (a condition with a payload).
interrupt FooCalcInt { x: Integer }

// 2. A function that may raise it declares `interrupts`. `signal` raises it;
//    the `recover { }` block is the inline restart — it runs only if a handler
//    chooses to recover, in this (suspended) function's own frame.
consumer foo(n: Integer) interrupts FooCalcInt {
    if n > 20 {
        signal FooCalcInt { x: n } recover {
            system.stdout.writeln("recovering; clamped " + n)
        }
    }
    system.stdout.writeln("foo continues normally")   // reached after recover
}

// 3. Handle it. The catch body DECIDES; it does not contain the recovery code.
try {
    foo(24)
} catch e: FooCalcInt {
    if e.x > 100 { skip }      // abandon the rest of foo; resume after `try`
    else         { recover }   // resume foo: run its recover{} block, continue
}
```

### Grammar (sketch)

```
interrupt_decl ::= "interrupt" Ident "{" field ("," field)* "}"
signal_stmt    ::= "signal" Type "{" fields "}" "recover" block
func_decl      ::= ... ("interrupts" Type ("," Type)*)? block
try_stmt       ::= "try" block ("catch" Ident ":" Type block)+
resolution     ::= "skip" | "recover"
```

`catch` is paren-free (like `if`/`for`); the payload uses the compound-type
literal `{ field: value }`.

## Semantics

### Resolutions

- **`recover`** — run the `recover { }` block at the signal site, then continue
  the signalling function at the statement *after* the `signal`. The recovery
  logic lives with the code that knows how to recover; the handler only opts in.
- **`skip`** — unwind from the signal site back to the `try`; the signalling
  function's remaining work is abandoned. Control resumes after the
  `try`/`catch`.
- **`retry`** — *deferred* (not in the first version): would re-execute the
  interrupting operation.

A `catch` body must select exactly one resolution (`skip` or `recover`) on every
path. It may run other statements first (e.g. logging) — subject to the
restriction below.

### Handler lookup

`signal T` searches the dynamically-enclosing handler stack for the nearest
`try` whose `catch` matches `T` (by type). The matching handler runs **without
unwinding** and returns a resolution, which the signal site then enacts. If no
handler matches, the signal is **unhandled** (see checked signatures).

### The `interrupts` annotation

- A function that may signal declares `interrupts T` (multiple: `interrupts A, B`).
- An interrupt that reaches `main` with no matching handler is a **panic**
  (`xc: unhandled interrupt: T`).

> The annotation is currently **parsed but not enforced** — the compiler does not
> yet verify that every `signal` site is declared, nor that callers handle or
> re-declare. That effect-checking pass is future work; today `interrupts T` is
> documentation that the runtime backs up with the unhandled-panic.

### Purity

Signalling is an effect, permitted only in the impure kinds — `consumer`,
`producer`, `creator` (and `entry`). The pure kinds — `mapper`, `projector`,
`predicate`, `reducer` — may neither `signal` nor call an `interrupts` function.
This reuses Xi's existing purity line.

### The catch-as-function restriction

To run a handler *before* unwinding (so `recover` can resume the suspended
frame), the `catch` body is compiled as a function over the payload. A `catch`
body may therefore read:

- the interrupt payload (`e`),
- module-level / global state,
- and call functions,

but **may not capture `try`-scope local variables** (Xi has no closures). This is
the simplification that makes resumption implementable without continuations or
coroutines. (Future work could lift it with explicit captures.)

## Worked example

```x
interrupt RateLimited { retryAfter: Integer }

producer fetch(url: String) interrupts RateLimited {
    let r = http.get(url)?
    if r.status == 429 {
        signal RateLimited { retryAfter: 5 } recover {
            system.stdout.writeln("backing off, then continuing")
        }
    }
    // ... use r ...
}

consumer run() {
    try {
        fetch("http://example.com/")
    } catch e: RateLimited {
        system.stdout.writeln("rate limited; retryAfter=" + e.retryAfter)
        recover            // resume fetch: it runs its backoff and continues
    }
}
```

## Static checks / diagnostics

- `signal T` in a function not declaring `interrupts T` → error (suggest adding
  it or wrapping in `try`).
- Calling an `interrupts T` function without handling or re-declaring `T` → error.
- `signal` / calling an `interrupts` function from a pure kind → error.
- `catch` body capturing a `try`-local → error (restriction explained).
- `catch` body that does not select a resolution on all paths → error.

## Limitations & future work

- **`retry`** resolution (re-execute the interrupting operation).
- **Value-producing signals** (`use-value`): `let y = signal T {..} recover {..}`
  where the recover block yields the value of the signal expression.
- **Value-producing `try`** (the try block yielding a result; today a statement).
- **Multiple named restarts** at one site (beyond a single `recover`).
- **Closures in `catch`** to lift the local-capture restriction.
- Interaction with `async`.

## Decisions on record

- Raise with **`signal`**; declare capability with **`interrupts T`**; type
  keyword is **`interrupt`**.
- Resolutions are **`skip`** (abandon) and **`recover`** (resume); `retry`
  deferred.
- Recovery code is an **inline `recover { }` restart at the signal site**; the
  handler only chooses.
- Execution model: the signalling function **suspends** and resumes only after
  an enclosing handler decides.
- Interrupts are **checked**; pure kinds may not signal.
- First version implements **`skip` + `recover`**. Ship this proposal first.
