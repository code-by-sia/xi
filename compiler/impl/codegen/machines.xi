// xc codegen — state-machine helpers.
//
// Single responsibility: lowering `machine` declarations — resolving a state
// name to its discriminant index, building the C condition for a (comma-joined)
// set of states, and typing/casting `data` fields. These are operations on a
// `MachineSpec`; the comma-separated state-set membership test is an operation
// on the CSV String.

mapper MachineSpec.stateIndex(name: String) -> Integer {
    let i = 0
    let n = stringArrLen(this.states)
    while i < n {
        if stringArrGet(this.states, i) == name { return i }
        i = i + 1
    }
    return 0 - 1
}

// Build a C condition over comma-joined state names: (self.__state == i) || ...
mapper MachineSpec.stateCond(csv: String) -> String {
    let cond = ""
    let start = 0
    let i = 0
    let n = string_len(csv)
    while i <= n {
        let isSep = false
        if i == n { isSep = true } else { if string_char_at(csv, i) == 44 { isSep = true } }
        if isSep {
            let nm = string_slice(csv, start, i)
            if string_len(nm) > 0 {
                if string_len(cond) > 0 { cond = cond + " || " }
                cond = cond + "(self.__state == " + int_to_string(this.stateIndex(nm)) + ")"
            }
            start = i + 1
        }
        i = i + 1
    }
    if string_len(cond) == 0 { cond = "0" }
    return cond
}

// The C type of a machine `data` field ("" if absent), from "name:ctype" pairs.
mapper MachineSpec.dataFieldCtype(fname: String) -> String {
    let i = 0
    let n = stringArrLen(this.dataFields)
    while i < n {
        let f = stringArrGet(this.dataFields, i)
        let colon = findChar(f, 58)
        if string_slice(f, 0, colon) == fname { return string_slice(f, colon + 1, string_len(f)) }
        i = i + 1
    }
    return ""
}

// An empty array literal `[]` lowers to an untyped `{0}`; in a typed assignment
// (machine data init/update) cast it to the field's type so C accepts it.
mapper MachineSpec.castEmptyArr(fname: String, e: ExprRes) -> String {
    if e.xtyp == "emptyarr" {
        let fct = this.dataFieldCtype(fname)
        if string_len(fct) > 0 { return "(" + fct + "){0}" }
    }
    return e.code
}

// True if `name` appears in a comma-joined list of state names.
predicate String.csvHasState(name: String) {
    let start = 0
    let i = 0
    let n = string_len(this)
    while i <= n {
        let isSep = i == n
        if not isSep { if string_char_at(this, i) == 44 { isSep = true } }
        if isSep {
            if string_slice(this, start, i) == name { return true }
            start = i + 1
        }
        i = i + 1
    }
    return false
}
