// Per-state data on a machine: make a `data` field a sum type and `update` it
// per transition, so each state carries the payload that makes sense for it.
//
//   xc examples/machine_phase_demo.xi && ./build/machine_phase_demo
import "std/log.xi"
import "std/convert.xi"

type Phase =
    | Idle
    | Running { since: Integer }
    | Done

machine Job {
    states  New, Active, Finished
    initial New
    terminal -
    data { phase: Phase = Idle }

    begin(t: Integer) : New    -> Active   update { phase: Running { since: t } }
    finish            : Active  -> Finished update { phase: Done }
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let j = Job.start().begin(100)
    match j.data.phase {
        Running r -> { logger.print("active, running since " + int_to_string(r.since)) }
        Idle      -> { logger.print("idle") }
        Done      -> { logger.print("done") }
    }

    let k = j.finish()
    match k.data.phase {
        Done      -> { logger.print("finished") }
        Running r -> { logger.print("still running since " + int_to_string(r.since)) }
        Idle      -> { logger.print("idle") }
    }
    return 0
}

module MachinePhaseDemo {}
