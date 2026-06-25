// Feature: ranges in for-loops — `..`, `until`, `downTo`, `step`.
mapper sumRange() -> Integer { let s = 0  for i in 1..5 { s = s + i }  return s }
mapper sumUntil() -> Integer { let s = 0  for i in 0 until 5 { s = s + i }  return s }
mapper countDown() -> Integer { let s = 0  for i in 10 downTo 6 { s = s + 1 }  return s }
mapper sumStep() -> Integer { let s = 0  for i in 0..10 step 2 { s = s + i }  return s }

test "inclusive range 1..5" { assertEq(sumRange(), 15) }
test "exclusive range until" { assertEq(sumUntil(), 10) }   // 0+1+2+3+4
test "downTo counts" { assertEq(countDown(), 5) }            // 10,9,8,7,6
test "stepped range" { assertEq(sumStep(), 30) }             // 0+2+4+6+8+10
