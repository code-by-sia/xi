// SpecArrays — growable typed-array primitives for the parser's spec structs
// (FieldSpec, TypeSpec, FuncSpec, ...). Injectable wrapper over the spec-array
// FFI; implemented by StdSpecArrays (impl/ffi/arrays/spec_arrays.xi).
//
// Its current callers are the parser/codegen free functions (which use the
// externs directly); the wrapper exists so the abstraction is complete and can
// be injected once those become class methods.
interface SpecArrays {
    mapper pushField(arr: FieldSpec[], s: FieldSpec) -> FieldSpec[]
    mapper pushMethod(arr: MethodSpec[], s: MethodSpec) -> MethodSpec[]
    mapper methodLen(arr: MethodSpec[]) -> Integer
    mapper methodAt(arr: MethodSpec[], i: Integer) -> MethodSpec
    mapper pushType(arr: TypeSpec[], s: TypeSpec) -> TypeSpec[]
    mapper typeLen(arr: TypeSpec[]) -> Integer
    mapper typeAt(arr: TypeSpec[], i: Integer) -> TypeSpec
    mapper pushIface(arr: IfaceSpec[], s: IfaceSpec) -> IfaceSpec[]
    mapper ifaceLen(arr: IfaceSpec[]) -> Integer
    mapper ifaceAt(arr: IfaceSpec[], i: Integer) -> IfaceSpec
    mapper pushDep(arr: DepSpec[], s: DepSpec) -> DepSpec[]
    mapper depLen(arr: DepSpec[]) -> Integer
    mapper depAt(arr: DepSpec[], i: Integer) -> DepSpec
    mapper pushClass(arr: ClassSpec[], s: ClassSpec) -> ClassSpec[]
    mapper classLen(arr: ClassSpec[]) -> Integer
    mapper classAt(arr: ClassSpec[], i: Integer) -> ClassSpec
    mapper pushBind(arr: BindSpec[], s: BindSpec) -> BindSpec[]
    mapper bindLen(arr: BindSpec[]) -> Integer
    mapper bindAt(arr: BindSpec[], i: Integer) -> BindSpec
    mapper pushModule(arr: ModuleSpec[], s: ModuleSpec) -> ModuleSpec[]
    mapper moduleLen(arr: ModuleSpec[]) -> Integer
    mapper moduleAt(arr: ModuleSpec[], i: Integer) -> ModuleSpec
    mapper pushFunc(arr: FuncSpec[], s: FuncSpec) -> FuncSpec[]
    mapper funcLen(arr: FuncSpec[]) -> Integer
    mapper funcAt(arr: FuncSpec[], i: Integer) -> FuncSpec
    mapper pushAtom(arr: AtomSpec[], s: AtomSpec) -> AtomSpec[]
    mapper atomLen(arr: AtomSpec[]) -> Integer
    mapper atomAt(arr: AtomSpec[], i: Integer) -> AtomSpec
    mapper pushMachine(arr: MachineSpec[], s: MachineSpec) -> MachineSpec[]
    mapper machineLen(arr: MachineSpec[]) -> Integer
    mapper machineAt(arr: MachineSpec[], i: Integer) -> MachineSpec
    mapper pushTransition(arr: MachineTransition[], s: MachineTransition) -> MachineTransition[]
    mapper transitionLen(arr: MachineTransition[]) -> Integer
    mapper transitionAt(arr: MachineTransition[], i: Integer) -> MachineTransition
    mapper pushDecisionRow(arr: DecisionRow[], s: DecisionRow) -> DecisionRow[]
    mapper decisionRowCount(arr: DecisionRow[]) -> Integer
    mapper decisionRowAt(arr: DecisionRow[], i: Integer) -> DecisionRow
    mapper pushDecisionTable(arr: DecisionTable[], s: DecisionTable) -> DecisionTable[]
    mapper decisionTableCount(arr: DecisionTable[]) -> Integer
    mapper decisionTableAt(arr: DecisionTable[], i: Integer) -> DecisionTable
}
