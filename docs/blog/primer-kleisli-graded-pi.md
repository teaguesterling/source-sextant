# Primer: Kleisli Composition, Graded Monads, and the π-Calculus

*Background material for the Conversations Are Closures formal framework.*

---

## Part 1: Kleisli Composition

### Ordinary composition

Start with the simplest thing. You have two functions:

```
f : A → B
g : B → C
```

Composition is straightforward:

```
g ∘ f : A → C
(g ∘ f)(x) = g(f(x))
```

Feed `x` to `f`, feed the result to `g`. This works because `f`'s output type matches `g`'s input type. Composition is associative, and the identity function `id(x) = x` is a neutral element. Functions with composition form a **category** — the category **Set** (or **Hask** if you prefer).

### The problem: functions with effects

Now suppose your functions do something *extra*. They don't just return a value — they also produce a side channel of information.

**Example 1: Functions that might fail.**

```
parseAge : String → Maybe Int
lookupPerson : Int → Maybe Person
```

`parseAge` might fail (bad input). `lookupPerson` might fail (not found). You want to compose them: string → maybe person. But you can't just do `lookupPerson(parseAge(s))` because `parseAge` returns a `Maybe Int`, not an `Int`.

**Example 2: Functions that log.**

```
validate : Order → (Order, Log)
price    : Order → (Price, Log)
```

Each function returns its result *plus* some log messages. You want to compose them and get the combined log. But `price` expects an `Order`, not an `(Order, Log)`.

**Example 3: Functions that branch.**

```
moves : Position → [Position]
moves : Position → [Position]
```

From a chess position, there are multiple possible next positions. Composing two steps should give all positions reachable in two moves. But `moves` returns a list, not a single position.

In every case, the pattern is the same. You have functions of the shape:

```
A → M(B)
```

where `M` is some wrapper — `Maybe`, `(_, Log)`, `[]` — and ordinary composition doesn't work because the types don't line up.

### Kleisli composition: the fix

Given:

```
f : A → M(B)
g : B → M(C)
```

Define **Kleisli composition** `g ∘_K f : A → M(C)` as:

> Run `f`, unwrap the result from `M`, feed it to `g`, combine the `M` effects.

The specifics of "unwrap" and "combine" depend on what `M` is:

**Maybe:**
```
(g ∘_K f)(x) = case f(x) of
    Nothing → Nothing
    Just y  → g(y)
```
If `f` fails, short-circuit. Otherwise feed the result to `g`.

**Writer (with log monoid):**
```
(g ∘_K f)(x) = let (y, log₁) = f(x)
                   (z, log₂) = g(y)
               in  (z, log₁ ++ log₂)
```
Run `f`, run `g`, concatenate the logs.

**List:**
```
(g ∘_K f)(x) = concatMap g (f(x))
```
Apply `g` to every result of `f`, flatten.

### This is what `>>=` does

If you know Haskell, Kleisli composition is just `>>=` (bind) in disguise:

```haskell
(g <=< f) x = f x >>= g
```

`>>=` is "run the first thing, feed its result to the second thing, combine the effects." Kleisli composition packages this into a single composed function.

### The Kleisli category

Here's the punchline. For any monad `M`, the following forms a **category**:

- **Objects:** Types (`A`, `B`, `C`, ...)
- **Morphisms from A to B:** Functions `A → M(B)` (not plain functions — *effectful* functions)
- **Composition:** Kleisli composition `∘_K`
- **Identity:** `return : A → M(A)` (wrap a value in the trivial effect)

This is called the **Kleisli category** of `M`, written **C_M** or **Kl(M)**.

The category laws hold because the monad laws hold:
- Left identity: `return ∘_K f = f` (wrapping then immediately unwrapping does nothing)
- Right identity: `f ∘_K return = f` (unwrapping a trivially-wrapped value does nothing)
- Associativity: `h ∘_K (g ∘_K f) = (h ∘_K g) ∘_K f`

**Why this matters for the framework:** When we say "agent handoffs are Kleisli composition," we mean: each agent is a function `Input → Conv(Output)` — it takes an input and produces an output *plus log entries*. Composing two agents means: run the first, concatenate its log, feed the result to the second, concatenate that log too. The Kleisli category of the conversation (Writer) monad is the category where agents live and compose.

---

## Part 2: Graded Monads

### Motivation: monads that track *how much*

A regular monad says "this computation has effects." Full stop. `Maybe` says "this might fail." `Writer Log` says "this produces log entries." But it doesn't say *how many* log entries, or *what kind* of failure, or *which resources* were used.

What if we want to be more precise? What if the type system could track not just *that* there are effects, but *how much* or *what grade* of effect?

### A simple example: counted I/O

Suppose you want to track how many database queries a computation makes.

With a regular monad:
```
query : SQL → DB Result     -- "this uses the database"
```

With a graded monad:
```
query : SQL → DB_1 Result   -- "this uses the database exactly once"
```

The subscript `1` is the **grade**. Two queries composed:
```
f : A → DB_1 B
g : B → DB_1 C
g ∘ f : A → DB_2 C          -- 1 + 1 = 2
```

The grades *add* when you compose. The type tracks the total.

### The formal definition

A **graded monad** (Katsumata, 2014) is parameterized by a monoid `(E, ·, ε)`:

```
M_e(A)     for each grade e ∈ E

return : A → M_ε(A)                         -- pure computation has identity grade
bind   : M_e(A) → (A → M_f(B)) → M_{e·f}(B) -- grades compose via the monoid operation
```

Compare to a regular monad:
```
return : A → M(A)
bind   : M(A) → (A → M(B)) → M(B)
```

The only difference is the index. Regular monads are graded monads where the grading monoid is trivial (one element).

### The grading monoid

The monoid `(E, ·, ε)` determines what gets tracked:

| Grading monoid | What it tracks | `·` | `ε` |
|---|---|---|---|
| `(ℕ, +, 0)` | Count of operations | Addition | Zero ops |
| `(Bool, ∨, false)` | Whether effect occurred | "Either did" | "Neither did" |
| `(Set, ∪, ∅)` | Which resources used | Union | No resources |
| `(Lattice, ∨, ⊥)` | Permission level | Join (max) | No permissions |

The key property: `·` is associative with identity `ε`. This guarantees that composing three computations gives the same grade regardless of grouping — `(e · f) · g = e · (f · g)`.

### Example: permission-graded computation

Suppose agents have permission levels: `None < Read < Write < Admin`. This forms a lattice (join-semilattice with bottom). Grade computations by the minimum permission they require:

```
readFile  : Path → Agent_Read String
writeFile : Path → String → Agent_Write ()
listDir   : Path → Agent_Read [Path]
```

Composing `readFile` then `writeFile`:
```
readFile p >>= writeFile q : Agent_{Read ∨ Write} ()
                           = Agent_Write ()
```

The composite requires `Write` permission (the join/max). A computation graded `Read` can run in any context that grants at least `Read`. The grades propagate through composition and the type system enforces that you never exceed the granted permissions.

### Why grading matters for the framework

In the formal framework, the grading monoid is the **scope lattice**:

```
(S, ∨, ⊥)
```

where `S` is the set of scopes, `∨` is scope join (union of visibility), and `⊥` is the empty scope (sees nothing).

An agent with scope `s` lives in `Conv_s(A)`. Composing two agents with scopes `s` and `t` gives a computation in `Conv_{s∨t}(A)` — it can see everything either agent could see.

```
quartermaster : Task → Conv_s(Kit)
worker        : Kit  → Conv_t(Report)
pipeline      : Task → Conv_{s∨t}(Report)
```

The grade tracks *who can see what*. The type system ensures that scoping decisions are explicit and composable.

Pure values (`return`) have grade `⊥` — they require no visibility. This is Kleisli composition from Part 1, enriched with scope tracking.

---

## Part 3: The π-Calculus

### A different starting point

Parts 1 and 2 built up from functions: individual computations that compose sequentially. The π-calculus starts from a completely different place: **concurrent processes that communicate**.

Lambda calculus asks: "What can a single computation do?" The π-calculus asks: "What happens when multiple processes run simultaneously and talk to each other?"

### Processes and channels

The basic entities:

- **Processes** — things that run (agents, workers, services)
- **Names** — identifiers that serve as communication channels

A process can:
1. **Send** a message on a channel: `x̄⟨y⟩` — "send `y` on channel `x`"
2. **Receive** a message on a channel: `x(z)` — "receive on channel `x`, bind the result to `z`"
3. **Run in parallel** with another process: `P | Q` — "`P` and `Q` run concurrently"
4. **Create a new private channel**: `(νx)P` — "create a fresh channel `x`, only visible inside `P`"
5. **Do nothing**: `0` — the stopped process

### A tiny example

Two processes communicating:

```
P = x̄⟨hello⟩.0          -- send "hello" on channel x, then stop
Q = x(msg).print(msg).0  -- receive on x, print it, stop

P | Q                     -- run both in parallel
```

`P` sends, `Q` receives. They synchronize on channel `x`. After the interaction:

```
→ print(hello).0          -- Q got the message, P is done
```

### Restriction: private channels

This is where it gets interesting. `(νx)` creates a channel that *nobody outside can see*:

```
(νx)(x̄⟨secret⟩.0 | x(msg).process(msg).0)
```

Channel `x` is private — only the two processes inside the `(νx)` can use it. An outside observer can't send on `x`, can't receive on `x`, can't even name `x`. This is **lexical scoping for concurrent processes**.

Compare to a closure:
```javascript
function outer() {
    let x = "secret";          // x is private to this scope
    inner1(x);                  // can see x
    inner2(x);                  // can see x
}
// out here, x doesn't exist
```

The `(νx)` restriction in π-calculus plays the same role as `let` binding in lambda calculus: it creates a name, bounds its visibility, and prevents external access.

### Scope extrusion: the key mechanism

Here's what makes the π-calculus different from static scoping. Watch this:

```
(νx)(x̄⟨secret⟩.0 | z̄⟨x⟩.0) | z(ch).ch̄⟨attack⟩.0
```

Break this down:
- Inside `(νx)`: two processes. One sends `secret` on `x`. The other **sends the channel `x` itself** on the public channel `z`.
- Outside `(νx)`: a process that receives on `z`, gets a channel, and sends on it.

What happens? The inner process sends `x` — a *private name* — out on public channel `z`. The outer process receives it. Now the outer process has a reference to the private channel.

Before:
```
(νx)( x̄⟨secret⟩.0 | z̄⟨x⟩.0 ) | z(ch).ch̄⟨attack⟩.0
     ^^^^^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^^^^^^
     x is private here             can't see x
```

After:
```
(νx)( x̄⟨secret⟩.0 | 0 | x̄⟨attack⟩.0 )
     ^^^^^^^^^^^^^^^       ^^^^^^^^^^^^^^
     x is still here       NOW can see x!
```

The scope of `x` **extruded** — it grew to include a process that originally couldn't see it. The `(νx)` boundary moved outward to encompass the new participant. This is called **scope extrusion**.

Key properties:
- The scope expanded **because someone with access explicitly shared it**
- The name `x` didn't become globally public — only the specific recipient got it
- The expansion is **monotone** — once you can see `x`, you can't un-see it

### Why scope extrusion matters for agents

This is exactly what happens when a worker requests a tool from the quartermaster:

```
Worker (scope s):     "I need the dependency graph tool"
                      → sends a request on the quartermaster channel

Quartermaster:        receives request, decides to grant access
                      → sends the tool reference back

Worker (scope s'):    now has the tool in scope, s' ⊃ s
```

In π-calculus terms:
- The tool is a private name `(νtool)` — initially only the quartermaster can see it
- The quartermaster sends `tool` to the worker on their shared channel
- The worker now has `tool` in scope — scope extrusion occurred
- The scope boundary moved to include the worker

The formal framework's Definition 9.2 (tool request as continuation) is exactly this:

```
NeedTool name reason (Tool → Conv_s(a))
```

The continuation `Tool → Conv_s(a)` is the process waiting to receive on a channel. The quartermaster providing the tool is the scope extrusion step. The worker resuming with expanded scope `s'` is the post-extrusion state.

### Bisimulation (briefly)

How do you prove two processes behave "the same"? You can't just compare syntax — many different process expressions produce equivalent behavior.

A **bisimulation** is a relation `R` between processes such that: if `P R Q`, then every observable action `P` can take, `Q` can match, and vice versa, and the resulting processes are still related by `R`. Two processes are **bisimilar** (`P ~ Q`) if such a relation exists.

This is what the formal review meant by "a structural identity requires a bisimulation." To prove that agent conversations are *structurally identical* to closures, you'd need to define both as processes (or terms in some common framework) and exhibit a bisimulation between them. The blog post didn't do this — it showed a correspondence table, which is suggestive but not a proof.

The formal framework document takes the honest middle path: it characterizes the *structural correspondence with a described divergence* (monotonically growing capture vs. static capture), which is more precise than a table and less than a bisimulation.

---

## How the Three Connect

The framework uses all three:

1. **Kleisli composition** (Part 1) gives us agent pipelines — sequential composition of effectful computations over a shared log

2. **Graded monads** (Part 2) enrich Kleisli composition with scope tracking — the grade records what each agent can see, and composition joins the grades

3. **The π-calculus** (Part 3) handles what the graded monad currently can't — dynamic scope changes mid-computation. When a worker requests a tool, the scope *extrudes*. This is exactly the mechanism Milner formalized, and it's the missing piece in Problems 1+2 of the framework.

The theoretical gap is: the graded monad assigns a fixed scope `s` to a computation `Conv_s(A)`, but scope extrusion means `s` can grow to `s'` during execution. The framework needs a way to model scope transitions *within* a graded computation, not just between them. The π-calculus has the mechanism (scope extrusion). The question is how to integrate it into the graded monad structure.

---

## References

- Atkey, R. (2009). Parameterised notions of computation. *Journal of Functional Programming*, 19(3-4).
- Hewitt, C., Bishop, P., & Steiger, R. (1973). A universal modular ACTOR formalism for artificial intelligence. *IJCAI*.
- Katsumata, S. (2014). Parametric effect monads and semantics of effect systems. *POPL*.
- Milner, R. (1999). *Communicating and Mobile Systems: The Pi-Calculus*. Cambridge University Press.
- Moggi, E. (1991). Notions of computation and monads. *Information and Computation*, 93(1).
- Orchard, D., Wadler, P., & Eades, H. (2019). Unifying graded and parameterised monads. *arXiv:1907.10276*.
