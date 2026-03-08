# Scope Transitions: From Graded to Parameterized

*Working notes — proposed replacement for Sections 7 and 9 of the formal framework.*

---

## The Problem

The graded monad (Section 7) assigns a fixed scope to each computation:

```
Conv_s(A) = M* → A × M*
```

The scope `s` is static. Composing two agents joins their scopes:

```
bind : Conv_s(A) → (A → Conv_t(B)) → Conv_{s∨t}(B)
```

But this only tracks scope *accumulation* across sequential compositions. It can't express what happens when a worker requests a tool mid-execution — the scope grows from `s` to `s' ⊇ s` during a single computation. The current framework handles this through an ad hoc `expand` morphism (Section 9, Prop. 9.3) that sits outside the monadic structure.

## The Fix: Parameterized Monads

A **parameterized monad** (Atkey, 2009) indexes computations by two states — a pre-state and a post-state:

```
M(s, t, A)    -- starts in state s, ends in state t, produces A
```

The monad operations:

```
return : A → M(s, s, A)
bind   : M(s, t, A) → (A → M(t, u, B)) → M(s, u, B)
```

The crucial structure: `bind` requires the post-state of the first computation to match the pre-state of the second. States thread through like a pipeline:

```
s →[first computation]→ t →[second computation]→ u
```

### Relationship to graded monads

Orchard, Wadler & Eades (2019) showed that parameterized and graded monads are unified. Specifically:

- A **graded monad** over a monoid `(E, ·, ε)` is a parameterized monad over the one-object category whose morphisms are elements of `E`.
- A **parameterized monad** over a category `C` is a graded monad when `C` has only one object.

Our scope lattice `(S, ≤)` is a category with *multiple* objects — each scope `s ∈ S` is an object, and a morphism `s → t` exists iff `s ≤ t`. This gives us strictly more structure than the graded monad: we can track scope *transitions*, not just scope *accumulation*.

## The Construction

### Definition (Scope-parameterized conversation monad)

For scopes `s, t ∈ S` with `s ≤ t`, define:

```
Agent(s, t, A) = s(M*) → A × M* × (t - s)
```

where:
- The input `s(M*)` is the log filtered through scope `s` (what the agent can initially see)
- The output `A` is the computed value
- The output `M*` is the new log entries (appended to the shared log)
- The output `(t - s)` is a *witness* of the scope expansion — the new visibility the agent acquired

**Simplification.** For now, collapse the witness into the type indices and write:

```
Agent(s, t, A) = M* → A × M*
```

where the input is understood to be filtered through `s`, and the type indices `s, t` with `s ≤ t` record that the computation starts seeing `s` and ends seeing `t`. The constraint `s ≤ t` is enforced by construction — there is no `Agent(s, t, A)` when `s ≰ t`.

### Monad operations

**Return** — no scope change, no log output:

```
return : A → Agent(s, s, A)
return(a) = λl. (a, ε)
```

**Bind** — scope transitions compose:

```
bind : Agent(s, t, A) → (A → Agent(t, u, B)) → Agent(s, u, B)
bind(m, f) = λl. let (a, w₁) = m(l)            -- m sees scope s
                     (b, w₂) = f(a)(t(l · w₁))  -- f sees scope t (wider)
                 in  (b, w₁ · w₂)
```

The key line: `f(a)(t(l · w₁))`. The second computation sees:
1. The original log `l` plus what `m` appended (`w₁`)
2. Filtered through the *expanded* scope `t`, not the original `s`

The scope grew between `m` and `f`. This is the transition `s → t` made explicit.

**Composition in the Kleisli category** of this parameterized monad:

```
(g ∘_K f) : Agent(s, u, _)

where f : A → Agent(s, t, B)
      g : B → Agent(t, u, C)
```

The pipeline `s → t → u` threads through. Each agent can see at least as much as the previous one. Monotonicity is structural.

### Monad laws

These follow from:
1. The monoid laws for `(M*, ·, ε)` (log concatenation)
2. The category laws for `(S, ≤)` (scope transitions compose associatively, identity transitions exist)

*Proof sketch.*

Left identity: `bind (return a) f = f a`
```
bind (return a) f = λl. let (a', w₁) = return(a)(l)     -- = (a, ε)
                            (b, w₂)  = f(a')(s(l · ε))  -- = f(a)(s(l))
                        in (b, ε · w₂)                   -- = (b, w₂)
                  = f(a)
```
Uses: `ε` is the monoid identity, `s ≤ s` so the scope is unchanged. ✓

Right identity: `bind m return = m`
```
bind m return = λl. let (a, w₁) = m(l)
                        (b, w₂) = return(a)(t(l · w₁))  -- = (a, ε)
                    in (b, w₁ · ε)                        -- = (a, w₁)
              = m
```
Uses: `t ≤ t` for return's trivial transition, `w · ε = w`. ✓

Associativity: `bind (bind m f) g = bind m (λa. bind (f a) g)` — follows from associativity of `·` on `M*` and composition of morphisms in `S`. ✓

## Scope Extrusion as a Primitive

With parameterized monads, scope expansion is no longer an ad hoc `expand` morphism. It's a computation with a typed scope transition:

### Tool request

```
request_tool : ToolName → Agent(s, s ∨ t_tool, Tool)
```

Requesting a tool is a computation that:
- Starts in scope `s`
- Ends in scope `s ∨ t_tool` (the original scope joined with the tool's scope)
- Produces the `Tool` as its value

The scope transition `s → s ∨ t_tool` is in the type. The caller sees it. Composition propagates it.

### The quartermaster as scope transition handler

The quartermaster doesn't just produce a Kit — it produces a *scope transition*:

```
qm : Task → Agent(s_qm, s_qm, Kit(t_worker))
```

The quartermaster operates in its own scope `s_qm` (no scope change for itself). But the Kit it produces *contains* a scope `t_worker` — the scope the worker will operate in. The Kit is a *specification of a future scope transition*.

The worker:

```
worker : Kit(t) → Agent(t, t', Report)
```

The worker starts in scope `t` (given by the Kit) and may transition to `t' ≥ t` (via tool requests).

The full pipeline:

```
s_qm →[quartermaster]→ s_qm    (qm's scope doesn't change)
t    →[worker]→ t'              (worker's scope may grow)
```

These are *different scope tracks* — the quartermaster and worker don't share a scope transition chain. They share a *log* (via the Writer part) but have independent scope trajectories.

### This resolves the framework's gap

The graded monad (old Section 7) couldn't express scope change within a computation. The `expand` morphism (old Section 9) was an ad hoc patch.

The parameterized monad:
1. Makes scope transitions first-class in the type
2. Enforces monotonicity (s ≤ t) by construction
3. Composes scope transitions via bind
4. Subsumes the graded monad (fixed scope = trivial transition s → s)
5. Matches the π-calculus structure (scope extrusion = a typed scope transition)

## What This Doesn't Resolve

**Independent scope tracks.** The parameterized monad threads scope transitions sequentially: `s → t → u`. But the quartermaster and worker have *independent* scopes that don't chain — they operate in parallel on the same log with different visibility. The parameterized monad handles one agent's scope evolution. For multiple agents with independent scopes, we need either:

- A product of parameterized monads (one per agent)
- A move to the π-calculus directly (where parallel composition is native)
- Session types (which formalize multi-party communication protocols with typed channels)

This is the next open problem. The parameterized monad closes the gap for *sequential* scope transitions within one agent's execution. It doesn't yet handle the *concurrent* case where multiple agents evolve their scopes independently.

**The scope lattice itself can change.** When a new tool is loaded or a new communication channel is opened, the set of possible scopes grows. The lattice `S` is not static — it's more like a growing universe. This connects to nominal techniques (Pitts, 2013) and the ν-binder in the π-calculus. The parameterized monad indexes over a fixed category `S`. A fully dynamic treatment would need `S` itself to be a parameter.

---

## Revised Section 12 Assessment

**"Agents are closures."** The parameterized monad sharpens the characterization: PL closures are `Agent(s, s, A)` (static capture — no scope change). Agent closures are `Agent(s, t, A)` with `s ≤ t` (monotonically growing capture). The graded monad was a special case that couldn't express this. The parameterized monad captures the divergence precisely.

**"Handoffs are continuations."** Now cleaner: a continuation `A → Agent(t, u, B)` takes the output of an `Agent(s, t, A)` and continues with the expanded scope `t`. The scope transition is in the type. Tool requests are continuations with a scope expansion: `Tool → Agent(s ∨ t_tool, t', A)`.

**"The quartermaster constructs capture lists."** Sharpened: the quartermaster produces a scope specification (a Kit containing `t_worker`). The worker's parameterized monad is indexed starting from that scope. The quartermaster literally *parameterizes* the worker's computation.

---

## References

- Atkey, R. (2009). Parameterised notions of computation. *JFP*, 19(3-4).
- Katsumata, S. (2014). Parametric effect monads and semantics of effect systems. *POPL*.
- Milner, R. (1999). *Communicating and Mobile Systems: The Pi-Calculus*. Cambridge.
- Orchard, D., Wadler, P., & Eades, H. (2019). Unifying graded and parameterised monads. *arXiv:1907.10276*.
- Pitts, A. M. (2013). *Nominal Sets: Names and Symmetry in Computer Science*. Cambridge.
