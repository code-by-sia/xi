// Feature: pairs (`to`, .first/.second), zip / partition / unzip.
test "pair construction" {
    let p = "ada" to 36
    assertEq(p.first, "ada")
    assertEq(p.second, 36)
}
test "zip two lists" {
    let names = listOf("a", "b", "c")
    let ages  = listOf(1, 2, 3)
    let people = names.zip(ages)
    assertEq(people.len(), 3)
}
test "partition by predicate" {
    let nums = listOf(1, 2, 3, 4, 5, 6)
    let split = nums.partition { it % 2 == 0 }
    assertEq(split.first.len(), 3)    // evens
    assertEq(split.second.len(), 3)   // odds
}
