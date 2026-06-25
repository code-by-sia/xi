// StdSpecArrays — the default SpecArrays: wraps the parser spec-struct array FFI.
extern "C" {
    mapper appendFieldSpec(arr: FieldSpec[], s: FieldSpec) -> FieldSpec[]
    mapper appendMethodSpec(arr: MethodSpec[], s: MethodSpec) -> MethodSpec[]
    mapper methodSpecLen(arr: MethodSpec[]) -> Integer
    mapper methodSpecGet(arr: MethodSpec[], i: Integer) -> MethodSpec
    mapper appendTypeSpec(arr: TypeSpec[], s: TypeSpec) -> TypeSpec[]
    mapper typeSpecLen(arr: TypeSpec[]) -> Integer
    mapper typeSpecGet(arr: TypeSpec[], i: Integer) -> TypeSpec
    mapper appendIfaceSpec(arr: IfaceSpec[], s: IfaceSpec) -> IfaceSpec[]
    mapper ifaceSpecLen(arr: IfaceSpec[]) -> Integer
    mapper ifaceSpecGet(arr: IfaceSpec[], i: Integer) -> IfaceSpec
    mapper appendDepSpec(arr: DepSpec[], s: DepSpec) -> DepSpec[]
    mapper depSpecLen(arr: DepSpec[]) -> Integer
    mapper depSpecGet(arr: DepSpec[], i: Integer) -> DepSpec
    mapper appendClassSpec(arr: ClassSpec[], s: ClassSpec) -> ClassSpec[]
    mapper classSpecLen(arr: ClassSpec[]) -> Integer
    mapper classSpecGet(arr: ClassSpec[], i: Integer) -> ClassSpec
    mapper appendBindSpec(arr: BindSpec[], s: BindSpec) -> BindSpec[]
    mapper bindSpecLen(arr: BindSpec[]) -> Integer
    mapper bindSpecGet(arr: BindSpec[], i: Integer) -> BindSpec
    mapper appendModuleSpec(arr: ModuleSpec[], s: ModuleSpec) -> ModuleSpec[]
    mapper moduleSpecLen(arr: ModuleSpec[]) -> Integer
    mapper moduleSpecGet(arr: ModuleSpec[], i: Integer) -> ModuleSpec
    mapper appendFuncSpec(arr: FuncSpec[], s: FuncSpec) -> FuncSpec[]
    mapper funcSpecLen(arr: FuncSpec[]) -> Integer
    mapper funcSpecGet(arr: FuncSpec[], i: Integer) -> FuncSpec
    mapper appendAtomSpec(arr: AtomSpec[], s: AtomSpec) -> AtomSpec[]
    mapper atomSpecLen(arr: AtomSpec[]) -> Integer
    mapper atomSpecGet(arr: AtomSpec[], i: Integer) -> AtomSpec
    mapper appendMachineSpec(arr: MachineSpec[], s: MachineSpec) -> MachineSpec[]
    mapper machineSpecLen(arr: MachineSpec[]) -> Integer
    mapper machineSpecGet(arr: MachineSpec[], i: Integer) -> MachineSpec
    mapper appendMachineTransition(arr: MachineTransition[], s: MachineTransition) -> MachineTransition[]
    mapper machineTransLen(arr: MachineTransition[]) -> Integer
    mapper machineTransGet(arr: MachineTransition[], i: Integer) -> MachineTransition
    mapper appendDecisionRow(arr: DecisionRow[], s: DecisionRow) -> DecisionRow[]
    mapper decisionRowLen(arr: DecisionRow[]) -> Integer
    mapper decisionRowGet(arr: DecisionRow[], i: Integer) -> DecisionRow
    mapper appendDecisionTable(arr: DecisionTable[], s: DecisionTable) -> DecisionTable[]
    mapper decisionTableLen(arr: DecisionTable[]) -> Integer
    mapper decisionTableGet(arr: DecisionTable[], i: Integer) -> DecisionTable
}

class StdSpecArrays implements SpecArrays {
    deps {}
    mapper pushField(arr: FieldSpec[], s: FieldSpec) -> FieldSpec[] { return appendFieldSpec(arr, s) }
    mapper pushMethod(arr: MethodSpec[], s: MethodSpec) -> MethodSpec[] { return appendMethodSpec(arr, s) }
    mapper methodLen(arr: MethodSpec[]) -> Integer { return methodSpecLen(arr) }
    mapper methodAt(arr: MethodSpec[], i: Integer) -> MethodSpec { return methodSpecGet(arr, i) }
    mapper pushType(arr: TypeSpec[], s: TypeSpec) -> TypeSpec[] { return appendTypeSpec(arr, s) }
    mapper typeLen(arr: TypeSpec[]) -> Integer { return typeSpecLen(arr) }
    mapper typeAt(arr: TypeSpec[], i: Integer) -> TypeSpec { return typeSpecGet(arr, i) }
    mapper pushIface(arr: IfaceSpec[], s: IfaceSpec) -> IfaceSpec[] { return appendIfaceSpec(arr, s) }
    mapper ifaceLen(arr: IfaceSpec[]) -> Integer { return ifaceSpecLen(arr) }
    mapper ifaceAt(arr: IfaceSpec[], i: Integer) -> IfaceSpec { return ifaceSpecGet(arr, i) }
    mapper pushDep(arr: DepSpec[], s: DepSpec) -> DepSpec[] { return appendDepSpec(arr, s) }
    mapper depLen(arr: DepSpec[]) -> Integer { return depSpecLen(arr) }
    mapper depAt(arr: DepSpec[], i: Integer) -> DepSpec { return depSpecGet(arr, i) }
    mapper pushClass(arr: ClassSpec[], s: ClassSpec) -> ClassSpec[] { return appendClassSpec(arr, s) }
    mapper classLen(arr: ClassSpec[]) -> Integer { return classSpecLen(arr) }
    mapper classAt(arr: ClassSpec[], i: Integer) -> ClassSpec { return classSpecGet(arr, i) }
    mapper pushBind(arr: BindSpec[], s: BindSpec) -> BindSpec[] { return appendBindSpec(arr, s) }
    mapper bindLen(arr: BindSpec[]) -> Integer { return bindSpecLen(arr) }
    mapper bindAt(arr: BindSpec[], i: Integer) -> BindSpec { return bindSpecGet(arr, i) }
    mapper pushModule(arr: ModuleSpec[], s: ModuleSpec) -> ModuleSpec[] { return appendModuleSpec(arr, s) }
    mapper moduleLen(arr: ModuleSpec[]) -> Integer { return moduleSpecLen(arr) }
    mapper moduleAt(arr: ModuleSpec[], i: Integer) -> ModuleSpec { return moduleSpecGet(arr, i) }
    mapper pushFunc(arr: FuncSpec[], s: FuncSpec) -> FuncSpec[] { return appendFuncSpec(arr, s) }
    mapper funcLen(arr: FuncSpec[]) -> Integer { return funcSpecLen(arr) }
    mapper funcAt(arr: FuncSpec[], i: Integer) -> FuncSpec { return funcSpecGet(arr, i) }
    mapper pushAtom(arr: AtomSpec[], s: AtomSpec) -> AtomSpec[] { return appendAtomSpec(arr, s) }
    mapper atomLen(arr: AtomSpec[]) -> Integer { return atomSpecLen(arr) }
    mapper atomAt(arr: AtomSpec[], i: Integer) -> AtomSpec { return atomSpecGet(arr, i) }
    mapper pushMachine(arr: MachineSpec[], s: MachineSpec) -> MachineSpec[] { return appendMachineSpec(arr, s) }
    mapper machineLen(arr: MachineSpec[]) -> Integer { return machineSpecLen(arr) }
    mapper machineAt(arr: MachineSpec[], i: Integer) -> MachineSpec { return machineSpecGet(arr, i) }
    mapper pushTransition(arr: MachineTransition[], s: MachineTransition) -> MachineTransition[] { return appendMachineTransition(arr, s) }
    mapper transitionLen(arr: MachineTransition[]) -> Integer { return machineTransLen(arr) }
    mapper transitionAt(arr: MachineTransition[], i: Integer) -> MachineTransition { return machineTransGet(arr, i) }
    mapper pushDecisionRow(arr: DecisionRow[], s: DecisionRow) -> DecisionRow[] { return appendDecisionRow(arr, s) }
    mapper decisionRowCount(arr: DecisionRow[]) -> Integer { return decisionRowLen(arr) }
    mapper decisionRowAt(arr: DecisionRow[], i: Integer) -> DecisionRow { return decisionRowGet(arr, i) }
    mapper pushDecisionTable(arr: DecisionTable[], s: DecisionTable) -> DecisionTable[] { return appendDecisionTable(arr, s) }
    mapper decisionTableCount(arr: DecisionTable[]) -> Integer { return decisionTableLen(arr) }
    mapper decisionTableAt(arr: DecisionTable[], i: Integer) -> DecisionTable { return decisionTableGet(arr, i) }
}
