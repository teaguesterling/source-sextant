# Actor Taxonomy

*Formal definitions of the participant types in the conversation framework.*

---

## Preamble: Why "Actor"

We use "actor" in the sense of Hewitt (1973): an entity with private state that communicates via message passing. This is more precise than "agent" (which implies inference) and more general than "process" (which implies a specific computational model). Every participant in a conversation — human, model, tool, orchestrator — is an actor with a scope, capabilities, and communication channels.

---

## The Central Axis: *Ma*

*Ma* (間) — the space between, the negative space, the part that's invisible — is the single axis along which actors vary. It is the **total opacity** of an actor: everything that influences their output but isn't observable by other participants.

*Ma* unifies several concepts that are often treated separately:

| Facet | What it means | More *ma* → |
|---|---|---|
| **Hiddenness** | How much internal state is unobservable | More hidden state |
| **Temperature** | How wide the output distribution is | More possible outputs |
| **Context** | How much invisible state influences output | Richer but less predictable |
| **Judgment** | Ability to decide from inaccessible information | Better judgment, harder to verify |
| **Predictability** | How well output follows from observable inputs | Less predictable |
| **Identity** | How inseparable the behavior is from the actor | More constitutive |

These aren't independent dimensions. They move together. An actor with more hidden state has wider output distributions, richer judgment, less predictability, and behavior that's harder to separate from who it is. They are facets of one thing.

### *Ma* determines role

The role an actor naturally plays in a conversation is a consequence of its *ma*:

```
borrowed ma ——→ minimal ma ——→ intrinsic ma ——→ constitutive ma
   |                |               |                  |
   ↓                ↓               ↓                  ↓
 execute         mediate          propose            authorize
(predictable)  (transparent)    (creative but      (judgment from
                                 bounded)          inaccessible context)
```

- You put the **low-*ma*** actor at the hub because you need the hub to be predictable and transparent.
- You put the **high-*ma*** actor at the authorization boundary because only it can make judgment calls that require inaccessible context.
- You constrain the **medium-*ma*** actor to proposing, not deciding, because its inference is rich but bounded.
- You sandbox the **minimal-*ma*** actor because its behavior is predictable given its inputs.

The conversation topology — who talks to whom, who mediates, who authorizes — follows from the *ma* structure. Architecture is a consequence of opacity.

### Kinds of *ma*

Every actor has *ma*, but the *kind* differs:

- **Borrowed *ma***: The Executor's hidden state is not its own — it's the world's. The filesystem, the clock, the network. Given the same inputs and the same world state, the output is determined. The opacity comes from the environment, not the actor.
- **Minimal *ma***: The [Fourth Actor]'s rules and Conv_State are in principle transparent. Its decisions follow from observable state. But "in principle" does real work — the Conv_State is complex enough that the decisions aren't always obvious to other actors.
- **Intrinsic *ma***: The Inferencer's weights, activations, and sampling are internal. The opacity comes from the inference process itself. Even given identical inputs and world state, the output can vary.
- **Constitutive *ma***: The Principal's thoughts, experience, and physical state are inseparable from who they are. You can't reduce the opacity without reducing the Principal.

### When actors play unnatural roles

Actors can be constrained or delegated into roles that don't match their *ma*, but the mismatch leaks:

- A **CI pipeline as Principal** (minimal *ma* in the authorization role): Can only apply fixed rules, never exercise judgment. A worse Principal than a human because it has less *ma* to draw on.
- An **LLM-backed MCP tool as Executor** (intrinsic *ma* in the execution role): Less predictable than a true Executor. The Executor interface can't fully hide the inference underneath.
- A **sub-agent** (Inferencer constrained to Executor interface): The parent treats it as a function call, but the output varies in ways a true function wouldn't.

### Secondary properties

*Ma* is the central axis. Actors also vary in properties that describe the *circumstances* of participation rather than the actor's nature:

| Property | Description | Range |
|---|---|---|
| **Lifetime** | How long the actor persists | Single invocation → Session → Cross-session → Indefinite |
| **Representation** | What space the actor operates in | Token space, Message space, Physical space |
| **Scope width** | How much of the conversation the actor can observe | Arguments only → Token window → Conv_State → Physical world |

These correlate with *ma* in practice (higher *ma* actors tend to have broader scope and longer lifetime) but the correlation isn't definitional.

---

## Actor Types

### Principal

The entity on whose behalf the conversation happens.

**Defining properties:**
- **External scope**: Observes things the system can never fully access — physical world, business context, intent beyond what's been stated, prior experience.
- **Authorization authority**: The ultimate arbiter of permissions. Can grant or deny capability transitions for other actors.
- **Asymmetric representation**: Operates in physical space (or the calling system's space). Reads rendered output. Writes natural language (or structured API calls).

**What a Principal is NOT required to be:**
- Human. A Principal can be an API caller, a CI/CD pipeline, another AI system, a scheduled job, or a human at a keyboard.
- Present. A Principal can configure permissions in advance and leave the conversation to run autonomously (auto-allow mode).
- Singular. Multi-user scenarios have multiple Principals with potentially different authorities.

**The key invariant:** The Principal has scope that is *opaque to all other actors*. Even when the Principal communicates their intent, they transmit a lossy projection of their actual state. The gap between the Principal's full context and what they express is irreducible *ma*.

**Lifetime:** Outlives the conversation. The Principal exists before and after the session. Their persistent state (memory, preferences, project knowledge) spans conversations.

**Reads:** Rendered output — formatted text, tool call summaries, status indicators. A lossy projection of the conversation, filtered and formatted by the System.

**Writes:** Natural language text, permission decisions (grant/deny/configure), meta-commands (/compact, /clear, backgrounding decisions). Writes enter the conversation through the System, never directly into the log.

---

### Inferencer

An actor that performs non-deterministic inference. Reads a scoped representation of the conversation, produces structured output.

**Defining properties:**
- **Opaque inference**: The internal process — attention, sampling, chain-of-thought — is invisible to all other actors. You observe inputs and outputs, not the reasoning. This is the Inferencer's *ma*.
- **Non-deterministic**: Same inputs can produce different outputs. The inference process is underspecified — temperature, sampling strategy, and internal state mean the output is drawn from a distribution, not computed from a function.
- **Structured output**: Produces a response containing text content, tool-use proposals, and (optionally) thinking traces. This is not "writing to the log" — it's producing output that the System receives, routes, and appends.

**Representation:**
- **Reads in token space**: The Inferencer receives a tokenized sequence — the conversation flattened and encoded by the inference infrastructure (API + tokenizer). The Inferencer never sees structured messages, Conv_State, or the System's internal bookkeeping. It sees tokens.
- **Writes in message space**: The Inferencer's output is de-tokenized by the inference infrastructure into structured messages (text blocks, tool_use blocks, thinking blocks). The System receives these structured messages.
- **The boundary between token space and message space is the API/tokenizer**, which is part of the inference infrastructure, not the System. The System operates entirely in message space.

**Scope:** Whatever the System constructs. The Inferencer has no independent access to the conversation, the tool registry, or any external state. Its entire observable world is the token sequence the System provided. The System is the Inferencer's reality.

**Lifetime:** A single inference call (one turn). The Inferencer has no persistent state across turns — all continuity comes from the conversation log, which the System manages. (Fine-tuning and RLHF are out of scope here — they affect the Inferencer's weights, not its per-turn state.)

**What the Inferencer produces (not "writes"):**
- Text content → System renders for Principal, appends to log
- Tool-use proposals → System routes through permission gate
- Thinking traces → System handles per configuration (may append, may discard)

The Inferencer never directly mutates any shared state. All its output is mediated by the System.

---

### Executor

An actor that performs a specific computation. Takes inputs, produces outputs, no inference.

**Defining properties:**
- **Borrowed *ma***: The Executor's hidden state is not its own. A `Bash` tool running `date` returns different results every second — but the variation comes from the clock, not from the tool. A `Read` tool depends on filesystem state that could change between calls — but the tool itself is a pure function over that state. The Executor has *ma*, but it's the world's *ma* passing through, not *ma* the Executor generates.
- **Narrow scope**: Sees only its explicit inputs (arguments) and its sandbox (e.g., allowed filesystem paths, network access). Has no access to the conversation, other tool calls, or the System's state.
- **No negotiation**: Does not propose, request, or refuse. Receives a request, executes or fails, returns a result. Has no concept of permissions from its own perspective — the permission gate happens *before* the Executor is invoked.

**Representation:** Operates in its native space — filesystem, shell, network, database. Its inputs are structured arguments (usually strings/JSON). Its output is structured results. The System translates between message space and the Executor's native space.

**Scope:** Defined by its arguments + sandbox configuration. The sandbox (allowed_directories, network access, resource limits) is set by the System at invocation time. The Executor cannot expand its own scope.

**Lifetime:** Single invocation. Stateless across calls (though it may interact with stateful external systems like filesystems or databases).

**Examples:**
- `Read(file_path)` — reads a file, returns content
- `Bash(command)` — executes a shell command, returns stdout/stderr
- `Edit(file, old, new)` — modifies a file, returns success/failure
- MCP tool calls — dispatched to external servers, arguments in, result out
- `WebSearch(query)` — queries an external service

**The near-determinism caveat:** An Executor that calls an external service (web search, database query) may receive different results at different times. The Executor itself is deterministic — it faithfully dispatches and returns — but the external system introduces non-determinism. This is analogous to how `IO` wraps a deterministic dispatch mechanism around a non-deterministic world.

---

### [The Fourth Actor — name TBD]

The actor that orchestrates the conversation. Mediates all communication. Manages state. Constructs scopes.

*Working names: Mediator, Orchestrator, Conductor, Runtime, Kernel, Steward. None fully satisfactory. See discussion below.*

**Defining properties:**
- **Hub topology**: The only actor that communicates with all others. All Principal ↔ Inferencer communication routes through it. All Inferencer ↔ Executor communication routes through it. All permission negotiation routes through it. No other pair of actors communicates directly.
- **Full Conv_State visibility**: Sees the structured conversation state — message history, token counts, tool registry, permission configuration, MCP server connections, budget, backgrounded task handles. This is strictly more information than any other actor sees.
- **Scope construction**: Builds the Inferencer's token window. Decides what's included, what's compacted, what's excluded. The Inferencer's reality is the [Fourth Actor]'s construction.
- **Deterministic but consequential**: Rule-based, not neural. But its decisions — when to compact, how to batch permissions, when to inject promise results, what to include in the Inferencer's scope — are consequential. Different decisions produce different conversations.
- **Meta-level operations**: Can perform operations that no other actor can: compaction (lossy history transformation), tool loading/unloading, permission mode changes, scope reconstruction, promise injection.

**Representation:** Operates in message space. Receives structured messages from the Inferencer (via API). Sends structured messages to the Inferencer (via API). Renders output for the Principal. Dispatches calls to Executors. Manages Conv_State as a structured record.

**Scope:**
- Reads: Conv_State (full structured state), Principal's text input, Inferencer's structured output, Executor results.
- Does NOT see: Principal's physical/external state, Inferencer's internal inference process, Executor internals (only inputs/outputs).

**Lifetime:** The conversation session. Created when the session starts, destroyed when it ends. (Some state — memory files, configuration — persists through other mechanisms.)

**What it does, concretely:**
- Receives Principal input → appends to log → reconstructs Inferencer scope → invokes inference
- Receives Inferencer output → appends assistant message to log → renders text for Principal → routes tool proposals through permission gate
- Permission gate: checks configuration → if "ask", synchronizes with Principal → grants or denies
- Tool dispatch: invokes approved Executors (possibly in parallel) → collects results → appends to log OR holds as promises
- Promise management: holds backgrounded task handles → decides when to inject resolved results
- Budget management: tracks token usage → triggers compaction when needed
- Scope construction: selects which messages to include in the Inferencer's next window, applies compaction, orders content

**Why current names are unsatisfying:**
- *Mediator*: Undersells it. A mediator passes messages. This actor constructs realities.
- *Orchestrator*: Better, but implies coordination of equals. This actor is privileged — it has capabilities no other actor has.
- *Kernel*: Strong analogy (mediates I/O, manages resources, enforces permissions, schedules), but too loaded with OS connotations.
- *Runtime*: Accurate for the execution aspect but misses the agency aspect.
- *Steward*: Good for the "manages on behalf of" aspect but too passive.
- *Conductor*: Good for timing and composition but implies artistic interpretation, which overstates the inference capability.

**Open question:** Is the right name something that captures "constructs the world other actors operate in"? The [Fourth Actor] doesn't just mediate — it *builds the stage, sets the lighting, and decides when the curtain rises*. The Inferencer performs, but the [Fourth Actor] determines what the Inferencer sees when it looks out at the audience.

---

## Compositions

### Sub-agents

A sub-agent is not a fifth actor type. It is a **composition** that presents an Executor interface to its parent:

```
Sub-agent (external) ≈ Executor
Sub-agent (internal) = [Fourth Actor] + Inferencer + {Executors}
```

From the parent conversation:
- The sub-agent is invoked like an Executor: arguments in, result out
- The sub-agent's internal turns are invisible — *ma* from the parent's perspective
- The sub-agent may use tools, perform inference, even spawn sub-sub-agents internally
- Only the final result (and possibly a summary) propagates back to the parent

**Scope inheritance:** The sub-agent's [Fourth Actor] typically inherits:
- A subset of the parent's tool registry (scoped by the parent)
- The parent's permission configuration (or a restricted version)
- A subset of the parent's conversation context (the capture list)

What it does NOT inherit:
- The parent's full conversation history
- The parent's budget (it may get an allocated sub-budget)
- The parent [Fourth Actor]'s internal state

**Recursion:** Sub-agents can spawn sub-sub-agents. Each level is a composition that collapses to an Executor interface at its boundary. The nesting depth is theoretically unbounded but practically limited by budget and latency.

### The Tool-Inferencer Spectrum

The boundary between Executor and Inferencer is not sharp:

| Actor | Scope | Inference | Looks like |
|---|---|---|---|
| `Read(file)` | File path + sandbox | None | Pure Executor |
| `Bash(cmd)` | Command + shell env | None | Executor (near-deterministic) |
| `WebSearch(q)` | Query string | None internally, external non-determinism | Executor wrapping non-deterministic world |
| MCP tool (LLM-backed) | Arguments | Neural (hidden) | Executor interface, Inferencer internals |
| Sub-agent | Capture list + tools | Full inference loop | Executor interface, full conversation internally |

The spectrum runs from pure computation to full agency. The key structural distinction: **does the actor have opaque internal inference?** If yes, its output is drawn from a distribution. If no, its output is a function of its inputs (modulo external state).

---

## The Communication Topology

```
                Principal
                  ↕ (text, permissions, meta-commands)
            [Fourth Actor]
           ↙    ↕       ↘
    Executor₁  Inferencer  Executor₂
                           (sub-agent, internally:
                             [Fourth Actor]'
                               ↕
                             Inferencer'
                               ↕
                             Executor'₁)
```

All arrows pass through the [Fourth Actor]. The Inferencer and Executors never communicate directly. The Principal and Inferencer never communicate directly. The [Fourth Actor] is the sole point of mediation.

In a sub-agent, a nested [Fourth Actor]' replicates this topology internally. The parent [Fourth Actor] sees the sub-agent as an Executor. The sub-agent's [Fourth Actor]' is invisible to the parent.

---

## The Shared Structure: Read → Infer → Respond

The Principal and the Inferencer are more alike than different.

Both have the same process:

```
1. Read    — observe a scoped view of the conversation
2. Infer   — opaque internal process (thinking, reasoning, deciding)
3. Respond — produce a lossy projection of internal state as output
```

The user doesn't type what they're thinking. They observe the rendered conversation, think (opaquely — *ma*), and produce text that compresses their actual reasoning into what they choose to express. The gap between the user's full internal state and what they type is exactly the same structural gap as between the Inferencer's hidden layers and its output tokens.

| | Principal | Inferencer |
|---|---|---|
| Reads | Rendered output (physical space) | Token window (token space) |
| Infers | Biological, opaque, unbounded context | Neural, opaque, bounded context |
| Responds | Natural language text, permission decisions | Text + tool proposals |
| *Ma* | Everything they thought but didn't type | Everything computed but not output |
| Underspecification | Enormous — physical world, lived experience | Large — temperature, sampling, training |

The difference isn't structural — it's **scope and authority**:
- The Principal has *wider scope* (physical world) and *more authority* (can authorize)
- The Inferencer has *narrower scope* (token window) and *no authority* (can only propose)

But the **process** — read a scoped input, perform opaque inference, produce a lossy output — is identical. This is the monadic continuum from the blog post, made concrete in the actor model. Both are monadic computations with underspecified context. They differ in how *much* is underspecified, not in the structure of the computation.

This means the Executor and [Fourth Actor] are the structurally distinct cases — they have **no opaque inference**. The Executor is a function. The [Fourth Actor] is a deterministic rule system. Their outputs are (in principle) fully determined by their inputs. The Principal and Inferencer are the actors whose outputs are drawn from distributions conditioned on unobservable state.

**The spectrum, grounded in actors:**

```
Executor          [Fourth Actor]      Inferencer         Principal
(pure function)   (deterministic      (neural inference,  (biological inference,
                   rules, full         bounded opaque      unbounded opaque
                   Conv_State scope)   internal state)     internal state)

no ma ←————————————— increasing ma ——————————————→ maximal ma
deterministic ←——————————————————————————————→ maximally underspecified
```

The same structure at every point. The dial turns on how much of the computation is opaque and how much of the world is left unspecified by the inputs.

---

## Summary Table

| Property | Principal | Inferencer | Executor | [Fourth Actor] |
|---|---|---|---|---|
| Inference | External (human/system) | Neural/probabilistic | None | Deterministic (rules) |
| Scope | Physical world + rendered output | Token window (constructed) | Arguments + sandbox | Conv_State (full) |
| Authority | Grants/denies permissions | None — proposes only | None — executes only | Enforces on behalf of Principal |
| Lifetime | Cross-session | Single turn | Single invocation | Session |
| Representation | Physical/API space | Token space | Native (fs, shell, net) | Message space |
| Writes to log | Via [Fourth Actor] | Via [Fourth Actor] | Via [Fourth Actor] | Directly |
| Communication | ↔ [Fourth Actor] only | ↔ [Fourth Actor] only | ↔ [Fourth Actor] only | ↔ All |

**The asymmetry in the last row is the defining structural fact.** Only the [Fourth Actor] writes to the log directly. All other actors' contributions are mediated. The [Fourth Actor] is not just a participant — it is the substrate on which the other actors operate.

---

## References

- Hewitt, C., Bishop, P., & Steiger, R. (1973). A universal modular ACTOR formalism for artificial intelligence. *IJCAI*.
- Agha, G. (1986). *Actors: A Model of Concurrent Computation in Distributed Systems*. MIT Press.
