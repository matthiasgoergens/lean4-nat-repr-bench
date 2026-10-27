/-
Benchmark of the conversions of large `Nat`s to decimal; see PLAN.md.

  NatReprBench pilot                 prints a repetition table (one line per cell: k variant r)
  NatReprBench block <id> <table>    runs one randomised block, prints CSV rows
-/

def lcg (s : UInt64) : UInt64 := s * 6364136223846793005 + 1442695040888963407

/-- Combines 9-digit chunks `cs[lo:hi]` (most significant first) into one number. -/
partial def combine (cs : Array Nat) (lo hi : Nat) : Nat :=
  if hi - lo = 1 then cs[lo]! else
  let mid := (lo + hi) / 2
  combine cs lo mid * 10 ^ (9 * (hi - mid)) + combine cs mid hi

/-- A uniformly random `k`-digit number with a nonzero leading digit, from a generator seeded by `k`. -/
def randomNat (k : Nat) : Nat := Id.run do
  let mut s : UInt64 := lcg (k.toUInt64 + 0x9E3779B97F4A7C15)
  s := lcg s
  let lead := 1 + (s >>> 33).toNat % 9
  let rest := k - 1
  -- the first chunk holds the leading digit and `rest % 9` further digits
  let mut first := lead
  for _ in [0:rest % 9] do
    s := lcg s
    first := first * 10 + (s >>> 33).toNat % 10
  let mut cs : Array Nat := #[first]
  for _ in [0:rest / 9] do
    s := lcg s
    cs := cs.push ((s >>> 24).toNat % 1000000000)
  return combine cs 0 cs.size

inductive Variant | list | dc | ext | dc2
  deriving BEq, Repr

def Variant.name : Variant → String
  | .list => "list" | .dc => "dc" | .ext => "ext" | .dc2 => "dc2"

def Variant.ofName? : String → Option Variant
  | "list" => some .list | "dc" => some .dc | "ext" => some .ext | "dc2" => some .dc2
  | _ => none

def Variant.fn : Variant → (Nat → String)
  | .list => Nat.benchReprList
  | .dc => Nat.benchReprDC
  | .ext => Nat.benchReprExtern
  | .dc2 => Nat.benchReprDC

def allSizes : List Nat := [20, 30, 100, 1000, 10000, 100000, 1000000, 10000000]

/-- The largest size, settable with the environment variable `MAXK` (the non-GMP run stops early). -/
initialize maxK : IO.Ref Nat ← do
  IO.mkRef ((← IO.getEnv "MAXK").bind String.toNat? |>.getD 10000000)

def sizes : IO (List Nat) := do
  let m ← maxK.get
  return allSizes.filter (· ≤ m)

def cellsOf (sizes : List Nat) (maxList : Nat) : List (Nat × Variant) :=
  sizes.flatMap fun k =>
    (if k ≤ maxList then [(k, Variant.list)] else []) ++ [(k, .dc), (k, .ext), (k, .dc2)]

/-- Times `r` back-to-back calls of `f n`; returns nanoseconds and a checksum that keeps the calls live. -/
@[noinline] def timeCalls (f : Nat → String) (n : Nat) (r : Nat) : IO (Nat × Nat) := do
  let t0 ← IO.monoNanosNow
  let mut acc := 0
  for _ in [0:r] do
    acc := acc + (f n).utf8ByteSize
  let t1 ← IO.monoNanosNow
  return (t1 - t0, acc)

def shuffle (xs : Array α) (seed : UInt64) : Array α := Id.run do
  let mut a := xs
  let mut s := lcg (seed + 12345)
  for i in [0:a.size] do
    let j := a.size - 1 - i
    s := lcg s
    let r := (s >>> 33).toNat % (j + 1)
    a := a.swapIfInBounds j r
  return a

def checkAgree (cells : List (Nat × Variant)) (inputs : List (Nat × Nat)) : IO Unit := do
  for (k, n) in inputs do
    let expect := Nat.benchReprDC n
    unless expect.length == k do
      throw <| IO.userError s!"dc gave {expect.length} digits for k = {k}"
    for (k', v) in cells do
      if k' == k then
        unless v.fn n == expect do
          throw <| IO.userError s!"{v.name} disagrees with dc at k = {k}"

def pilot (cells : List (Nat × Variant)) (inputs : List (Nat × Nat)) : IO Unit := do
  for (k, v) in cells do
    let n := (inputs.lookup k).get!
    let mut r := 1
    repeat
      let (t, _) ← timeCalls v.fn n r
      if t ≥ 20000000 then break
      r := r * 2
    IO.println s!"{k} {v.name} {r}"

def parseTable (s : String) : List (Nat × Variant × Nat) :=
  s.splitOn "\n" |>.filterMap fun line =>
    match line.splitOn " " with
    | [k, v, r] => do pure (← k.toNat?, ← Variant.ofName? v, ← r.toNat?)
    | _ => none

def block (cells : List (Nat × Variant)) (id : Nat) (table : List (Nat × Variant × Nat))
    (inputs : List (Nat × Nat)) : IO Unit := do
  let order := shuffle cells.toArray id.toUInt64
  for h : i in [0:order.size] do
    let (k, v) := order[i]
    let n := (inputs.lookup k).get!
    let some (_, _, r) := table.find? (fun (k', v', _) => k' == k && v' == v)
      | throw <| IO.userError s!"no repetition count for {k} {v.name}"
    let (t, sum) ← timeCalls v.fn n r
    unless sum == r * k do throw <| IO.userError "checksum"
    IO.println s!"{id},{i},{k},{v.name},{r},{t}"
    (← IO.getStdout).flush

def main (args : List String) : IO Unit := do
  let sizes ← sizes
  let maxList := (← IO.getEnv "MAXLIST").bind String.toNat? |>.getD 100000
  let cells := cellsOf sizes maxList
  let inputs := sizes.map fun k => (k, randomNat k)
  checkAgree cells inputs
  match args with
  | ["pilot"] => pilot cells inputs
  | ["block", id, file] => block cells id.toNat! (parseTable (← IO.FS.readFile file)) inputs
  | _ => throw <| IO.userError "usage: NatReprBench pilot | block <id> <table>"
