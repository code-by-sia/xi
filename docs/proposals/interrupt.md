# Proposal: Interrupts (resumable conditions)

> **Status: Draft / not implemented.** This is a design document for review, not a
> shipped feature. Decisions captured here were agreed during design discussion;
> the implementation is future work.

## Summary

`interrupt` introduces **resumable conditions** to X. A function can `signal` an
interrupt; an enclosing `try`/`catch` decides — *with the interrupted function's
stack still alive* — whether to **`skip`** (abandon the rest of the function) or
**`recover`** (run a restart block at the signal site and continue). It is
**checked**: a function that may signal declares `signals T`, and the compiler
verifies callers either handle or re-declare it.

This is the Common Lisp condition/restart model (also seen in Smalltalk's
resumable exceptions and algebraic effects), adapted to X's C backend and its
pure/impure function-kind system.

## Motivation

X already has `Result` (`T!`, `ok`/`err`, `?`) for **expected, local** errors
handled as values. What it lacks is a way to handle a **cross-cutting,
recoverable** condition raised deep in a call stack, where an *outer* policy
decides what to do — without the inner code losing its place. Classic exceptions
unwind the stack before the handler runs, so the inner computation cannot be
resumed. Interrupts run the handler **before unwinding**, enabling recovery.

| Mechanism | Use | Stack behaviour |
|-----------|-----|-----------------|
| `Result` (`T!`) | expected errors, handled locally as values | none; caller inspects |
| **Interrupt** | recoverable conditions, outer policy decides | handler runs with the stack intact, then resumes or abandons |
| (classic exceptions) | — | would unwind before the handler; not in X |

## Syntax

```x
// 1. Declare an interrupt type (a condition with a payload).
interrupt FooCalcInt { x: Integer }

// 2. A function that may raise it declares `signals`. `signal` raises it; the
//    `recover { }` block is the inline restart, run only if a handler chooses
//    to recover.
consumer foo(n: Integer) signals FooCalcInt {
    if n > 20 {
        signal FooCalcInt { x: n } recover {
            system.stdout.writeln("recovering; clamped " + n)
        }
    }
    system.stdout.writeln("foo continues normally")   // reached after recover
}

// 3. Handle it. The catch body picks a resolution.
try {
    foo(24)
} catch e: FooCalcInt {
    if e.x > 100 { skip }      // abandon the rest of foo, resume after `try`
    else         { recover }   // run foo's recover{} block, then continue foo
}
```

### Grammar (sketch)

```
interrupt_decl ::= "interrupt" Ident "{" field ("," field)* "}"
signal_stmt    ::= "signal" Type "{" fields "}" ("recover" block)?
func_decl      ::= ... ("signals" Type ("," Type)*)? block
try_stmt       ::= "try" block ("catch" Ident ":" Type block)+
resolution     ::= "skip" | "recover"
```

## Semantics

### Resolutions

- **`skip`** — unwind the stack from the `signal` site back to the `try`; the
  interrupted function's remaining work is abandoned. Control resumes after the
  `try`/`catch`.
- **`recover`** — run the `recover { }` block located at the `signal` site, then
  continue the interrupted function at the statement *after* the `signal`.
- **`retry`** — *deferred* (not in the first version). It would re-execute the
  interrupting operation; semantics and progress guarantees need more design.

A `catch` body must end by selecting exactly one resolution (`skip` or
`recover`). It may run other statements first (e.g. logging) but see the
restriction below.

### Handler lookup

`signal T` searches the dynamically-enclosing handler stack for the nearest
`try` whose `catch` matches `T` (by type). The matching handler runs **without
unwinding** and returns a resolution, which the signal site then enacts. If no
handler matches, the signal is **unhandled** (see below).

### Checked signatures

- A function whose body can `signal T` (directly, or by calling a function that
  `signals T` without handling it) **must** declare `signals T`.
- `signals` accepts a list: `signals A, B`.
- `entry main` may not propagate interrupts; an interrupt that reaches `main`
  unhandled is a **panic** (aborts with a diagnostic).
- The compiler verifies catch types correspond to interrupts that can actually
  reach the `try`.

### Purity

Signalling is an effect. It is permitted only in the impure kinds — `consumer`,
`producer`, `creator` (and `entry`). The pure kinds — `mapper`, `projector`,
`predicate`, `reducer` — may neither `signal` nor call a `signals` function.
This reuses X's existing purity line.

### The catch-as-function restriction

To run a handler *before* unwinding (so `recover` can resume), the `catch` body
is compiled as a function over the payload. Therefore a `catch` body may read:

- the interrupt payload (`e`),
- module-level / global state,
- and call functions,

but **may not capture `try`-scope local variables** (X has no closures). This is
the key simplification that makes resumption implementable without continuations
or coroutines. (Future work could lift this with explicit captures.)

## Worked example

```x
interrupt RateLimited { retryAfter: Integer }

producer fetch(url: String) signals RateLimited {
    let r = http.get(url)?
    if r.status == 429 {
        signal RateLimited { retryAfter: 5 } recover {
            system.stdout.writeln("backing off")
        }
    }
    // ... use r ...
}

consumer run() {
    try {
        fetch("http://example.com/")
    } catch e: RateLimited {
        system.stdout.writeln("rate limited; retryAfter=" + e.retryAfter)
        recover            // let fetch run its backoff and continue
    }
}
```

## Implementation design (C backend)

Interrupts need **runtime + codegen** support — unlike decision tables, they
cannot be desugared into existing constructs.

**Runtime: a dynamic handler stack.**

```c
typedef enum { XC_SKIP = 0, XC_RECOVER = 1 } xc_resolution_t;

typedef struct xc_handler {
    int               type_id;     /* which interrupt type this catch matches */
    xc_resolution_t (*fn)(void* payload);  /* compiled catch body */
    jmp_buf           unwind;      /* skip target (the try) */
    struct xc_handler* prev;
} xc_handler_t;

/* thread-local-ish global stack top */
static xc_handler_t* xc_handlers;
```

- **`try { BODY } catch e: T { CATCH }`** lowers to:
  1. compile `CATCH` to `xc_resolution_t __hN(T payload)` (returns the chosen
     resolution; reads payload/globals only),
  2. push `{ type_id(T), __hN, jb }`, `setjmp(jb)` (the `skip` landing),
  3. run `BODY`, then pop the handler.
- **`signal T { ... } recover { REC }`** lowers to:
  1. walk `xc_handlers` for the nearest matching `type_id`,
  2. if none → unhandled (panic, or propagate per `signals` — at `main`, abort),
  3. `res = handler->fn(&payload)`,
  4. `if (res == XC_RECOVER) { REC; /* fall through, continue */ }`
     `else /* XC_SKIP */ longjmp(handler->unwind, 1);`

`skip` uses `setjmp`/`longjmp` (well-trodden in the runtime already). `recover`
needs no unwinding — it just runs `REC` and continues — which is exactly why the
handler must be a callable function rather than inline code that touches
`try`-locals.

**Codegen** adds: interrupt struct typedefs + `type_id`s, the `signal` lowering,
the `try`/`catch` lowering (handler push/pop + setjmp + the compiled catch fn),
and `signals` checking in the type/effect pass.

## Static checks / diagnostics

- A `signal T` in a function not declaring `signals T` → error (suggest adding
  it or wrapping in `try`).
- A call to a `signals T` function that neither handles nor re-declares `T` →
  error.
- `signal`/calling a `signals` function from a pure kind → error.
- `catch` body that captures a `try`-local → error (with the restriction
  explained).
- `catch` body that does not select a resolution on all paths → error.

## Limitations & future work

- **`retry`** resolution (re-execute the interrupting operation).
- **Value-producing signals** (`use-value`): `let y = signal T {...} recover {
  ... }` where the recover block yields the value of the signal expression.
- **Value-producing `try`** (the try block yielding a result; today it is a
  statement).
- **Multiple named restarts** at one site (beyond a single `recover`).
- **Closures in `catch`** to lift the local-capture restriction.
- Interaction with `async`.

## Decisions on record

- First version implements **`skip` + `recover`** only; `retry` deferred.
- Interrupts are **checked** via `signals T` on function signatures.
- Ship this **proposal** for review before implementation.
