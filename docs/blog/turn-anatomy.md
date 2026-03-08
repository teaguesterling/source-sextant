# The Anatomy of a Turn

*Working notes — a concrete model of what actually happens in a conversation turn, grounded in how Claude Code works.*

---

## The Participants

Every conversation has (at least) three agents. Not metaphorical — three actual participants with distinct scopes, capabilities, and agency.

### The User

- **Scope**: The physical world. Their expertise, their project, their intent. Everything they know that isn't in the log.
- **Capabilities**: Provides goals. Grants/denies permissions. Backgrounds tasks. Reads and writes natural language.
- **What's invisible**: The model's system prompt. The client's internal state (token counts, compaction decisions). Tool implementation details.
- **Inference**: Internal, invisible. The user thinks, then types. The thinking is *ma*.

### The System (client/orchestrator)

- **Scope**: `Conv_State` — the structured conversation. Token counts, tool registry, permission configuration, MCP server connections, budget, backgrounded task handles.
- **Capabilities**: Mediates all communication. Manages permissions. Loads/unloads tools. Compacts history. Injects backgrounded results. Renders output. The only participant that talks to everyone.
- **What's invisible**: The user's physical state. The model's internal weights and inference process. The actual content of tool execution (it sees inputs and outputs, not internals).
- **Inference**: Programmatic. Rules, not neural. But still decision-making: *when* to compact, *how* to render, *whether* to batch permission prompts.

### The Model (agent)

- **Scope**: The token window — the flattened, filtered conversation as a token sequence. System prompt, instructions, conversation history (possibly compacted), tool descriptions, recent tool results.
- **Capabilities**: Inference. Proposes tool calls. Generates text. Can request multiple tools in parallel.
- **What's invisible**: Conv_State metadata (token counts, budget remaining). Permission configuration. MCP server topology. The user's physical world. Its own weights.
- **Inference**: Neural, internal, invisible to other participants. The model "thinks" then "responds." The thinking is *ma*.

### Tools (degenerate agents)

- **Scope**: Their inputs (arguments) plus their sandbox (filesystem access, network access, etc.).
- **Capabilities**: Narrow and specific. `Read` reads a file. `Bash` executes a command. An MCP tool calls an external service.
- **What's invisible**: Everything outside their inputs and sandbox. The conversation context. The model's intent. Other tool calls.
- **Inference**: Typically none (pure computation). But MCP tools can be backed by LLMs, and subagents *are* tools with full inference loops. The boundary between "tool" and "agent" is a spectrum.

**Key observation**: The System is the only participant that communicates with all others. The User and Model never interact directly — the System mediates. Tools never talk to the User — the System mediates. This star topology, with the System at the center, is the actual architecture.

```
        User
         ↕
       System ←→ Tool₁
         ↕    ←→ Tool₂
       Model  ←→ Tool₃
```

---

## The Turn Structure

A single conversation turn, fully expanded:

### Phase 1: Inference (Model, internal)

The Model reads its scoped view of the conversation — the token window the System constructed. It performs inference. This is invisible to all other participants. It produces a response: text and/or tool call proposals.

**In the framework**: This is the *ma* of the Model. The inference process is the complementary scope — it's what happens that nobody else sees. The output (text + tool proposals) is what enters the log.

### Phase 2: Proposal (Model → System)

The Model's response reaches the System. If it contains tool calls, each one is a **proposal**: "I want to use tool X with arguments Y."

Multiple proposals can be batched — the Model can propose N tool calls in a single response. These are independent: no proposal depends on another's result.

**In the framework**: Each proposal is a request for a capability — visibility (the tool exists) is already established, but authorization (permission to use it) must be checked.

### Phase 3: Permission Gate (System ↔ User)

For each proposal, the System checks the permission configuration:

- **Auto-allow**: No user interaction. The System authorizes immediately.
- **Auto-deny**: No user interaction. The System rejects immediately.
- **Ask**: The System renders the proposal for the User. The User evaluates and decides. This is a **synchronization point** between System and User.

For batched proposals, the System may batch the permission prompts: "The model wants to do A, B, and C. Allow all?"

**In the framework**: This is the protocol layer. It's not a monadic operation — it's a communication between the System and User that determines whether a state transition (scope expansion) is authorized. The User's decision is informed by the chain: tool availability → Model's intent → System's rendering → User's judgment.

**The rejected-then-approved pattern**: The Model proposes tool X, the User denies. The Model adjusts its approach, perhaps reproposing with different arguments or a different tool. Later, the User approves. What changed? Not the permission configuration (necessarily) — the User made a different judgment on a different invocation. The authorization landscape is not just stateful but *contextual*: the same tool with different arguments can get different decisions.

### Phase 4: Execution (System → Tools, parallel)

Approved tools execute. The System dispatches them — potentially in parallel. Each tool runs in its own scope (its inputs + sandbox). Tool execution is concurrent and independent.

**In the framework**: Each tool execution is a mini-agent computation: `Tool(args) → Result × Log`. The tools don't see each other. They don't see the conversation. They see their arguments and their sandbox. The System collects the results.

**Subagents are tools with inference**: A subagent tool call spawns a nested conversation — the subagent has its own turn loop (inference → propose → gate → execute → collect). The parent Model doesn't see the subagent's internal turns. Only the final result (and maybe a summary) propagates back. The subagent's internal conversation is *ma* from the parent's perspective.

### Phase 5: Collection — Barrier or Promise

Here's where the user's observation changes the model.

**Barrier collection (default)**: The System waits for all tool executions to complete. Results are collected. The System appends them to the log. The Model's next inference step sees all results. This is synchronous: propose → wait → receive → next turn.

**Promise collection (backgrounded)**: The User or Model indicates that a task should be backgrounded. The System doesn't wait. Instead:

1. The System creates a **promise handle** — a reference to the in-progress work.
2. The conversation continues. The Model begins its next inference step without the backgrounded result.
3. At some later point, the backgrounded task completes.
4. The **System decides when and how** to inject the result into the conversation.

This is crucial: the System has agency over *when* the promise resolves into the log. It might:
- Inject immediately at the next turn boundary
- Wait until the Model is idle
- Wait until the result is relevant to the current discussion
- Batch multiple resolved promises together
- Summarize or compact the result before injection

The System is not a dumb promise scheduler. It's an agent making decisions about when to introduce new information. This is quartermaster-like behavior: the System decides what the Model sees and when.

**What this means structurally**: The log is no longer strictly alternating turns. The System can inject content at turn boundaries, making the log a merge of multiple concurrent streams:

```
Log = Model turns ⊕ Tool results ⊕ System injections ⊕ User messages
```

These streams are ordered *within* each source but interleaved *across* sources. The System controls the interleaving. The Model sees whatever ordering the System presents in the token window.

### Phase 6: Append

Results (immediate or resolved promises) are appended to the log. The conversation state advances. The System may also perform meta-operations at this point: compaction if budget is low, tool set changes, permission updates.

### Phase 7: Scope Reconstruction

Before the next inference step, the System reconstructs the Model's scope:
- Apply compaction if needed (lossy — budget reclamation)
- Filter through the Model's visibility rules
- Flatten Conv_State into the token window
- Include or exclude backgrounded task status

This is the System acting as scope constructor — it builds the capture list for the Model's next closure.

→ Back to Phase 1.

---

## Parallel Tool Calls, Formally

When the Model proposes N tool calls in one response:

```
Propose: {tool₁(args₁), tool₂(args₂), ..., toolₙ(argsₙ)}
```

The System processes these as:

```
Gate:    perm₁ = check(tool₁), perm₂ = check(tool₂), ..., permₙ = check(toolₙ)
         (may involve User synchronization for "ask" permissions)

Execute: for each permᵢ = granted:
           resultᵢ = toolᵢ(argsᵢ)    -- concurrent
         for each permᵢ = denied:
           resultᵢ = PermissionError  -- immediate

Collect: barrier — wait for all resultᵢ
         OR promise — continue, inject later
```

Each tool execution is independent — they don't share scope, they can't see each other's results. They're parallel computations over disjoint scopes that merge results into the shared log.

In π-calculus terms:

```
(ν r₁)(ν r₂)...(ν rₙ)(
    tool₁(args₁, r₁) | tool₂(args₂, r₂) | ... | toolₙ(argsₙ, rₙ)
  | r₁(res₁).r₂(res₂)...rₙ(resₙ).continue(res₁, res₂, ..., resₙ)
)
```

Each tool gets a private result channel `rᵢ`. The continuation waits for all results (barrier) before proceeding. The channels are restricted — only the tool and the collector can use them.

For the promise variant, replace the barrier with:

```
  | r₁(res₁).inject(res₁) | r₂(res₂).inject(res₂) | ... | continue()
```

Each result is injected independently when it arrives. The continuation doesn't wait.

---

## Authorization as a Separate Structure

Pulling together the earlier observations: there are three independent axes.

**Visibility** — what exists in the agent's scope.
- Determined by: tool registry, MCP connections, Conv_State filtering
- Changed by: tool loading/unloading, MCP server reload, compaction
- Structure: scope lattice (monotone within a phase, can change at meta-level boundaries)

**Authorization** — what the agent is *permitted* to do.
- Determined by: permission configuration (auto/ask/deny per tool), allowed_directories, sandbox rules
- Changed by: user decisions, permission mode changes, configuration updates
- Structure: a **protocol** between System and User, not a static lattice. Context-dependent (same tool, different args → different decision).

**Capability** — what the agent can *actually do right now*.
- Capability = Visibility ∧ Authorization
- This is what the "scope" in the graded monad should actually track

The current framework models Visibility (scope lattice) but not Authorization (permission protocol). The permission protocol is where session types would contribute:

```
type ToolUseProtocol =
    Model  → System : Propose(tool, args)
  ; System → User   : PermissionCheck(tool, args)    -- only if mode = "ask"
  ; User   → System : Grant | Deny
  ; if Grant:
      System → Tool  : Execute(args)
    ; Tool   → System: Result(output)
    ; System → Model : ToolResult(output)
  ; if Deny:
      System → Model : PermissionDenied(tool, reason)
```

This protocol composes: N parallel tool calls are N parallel instances of this protocol, with the barrier/promise collection as the synchronization strategy.

---

## Where the Existing Framework Applies

| Turn Phase | Framework Section | Status |
|---|---|---|
| Inference (Model internal) | *ma* (Section 3) | Clean — complementary scope |
| Proposal (tool calls) | Kleisli morphisms (Section 6) | Clean — effectful functions |
| Permission gate | **Not modeled** | Needs session types or protocol model |
| Tool execution | Parameterized monad (scope-transitions.md) | Partially — tools are degenerate agents |
| Barrier collection | Kleisli composition | Clean — sequential |
| Promise collection | **Not modeled** | Needs futures/promises in the monad |
| System meta-operations | Section 10 (two-level structure) | Partially — endomorphisms on Conv_State |
| Scope reconstruction | Scope lattice + graded monad (Section 7) | Clean |

### Gaps

1. **The permission protocol** — cross-level negotiation between System and User. Session types.
2. **Promise/future injection** — backgrounded tasks that resolve later. The log becomes a merge of concurrent streams. The System controls the interleaving.
3. **The System as agent** — it has scope, makes decisions, and its decisions affect the other agents' scopes. The framework treats it as a meta-level operator, but it's actually a participant with agency.
4. **Authorization as a dynamic, contextual property** — not a static lattice. The same tool can be authorized or denied depending on arguments, conversation state, and user judgment.
5. **The tool-agent spectrum** — tools, subagents, and the Model are all agents with different scope widths and inference capabilities. The framework needs a uniform treatment.

---

## What We're Converging On

The conversation monad (Writer over append-only log) is the easy part. It handles the data flow.

The interesting structure is in three other places:

1. **The protocol layer** — how participants negotiate authorization and coordinate. Session types.
2. **The concurrency model** — parallel tool execution, backgrounded tasks, promise resolution. π-calculus.
3. **The System's agency** — scope construction, compaction timing, promise injection, permission mediation. The System is the most powerful participant and the least modeled.

The monadic framework (graded/parameterized) handles the sequential, data-flow aspects well. But the conversation is fundamentally a **multi-party concurrent protocol with negotiated authorization**, and that's a different beast. The next step is to model the protocol layer — starting with the permission negotiation — and see how it composes with the existing monadic structure.

---

## Open Questions

- Is the System a monad transformer? It wraps every interaction between other participants. Every Model ↔ Tool interaction goes through it. Every User ↔ Model interaction goes through it. It *transforms* the underlying monads by adding mediation.

- Are backgrounded tasks a free monad construction? A promise is "a computation that hasn't been evaluated yet" — which is exactly what the free monad provides: a description of a computation, separated from its execution.

- The Model's inference step is a black box in this model. But it's also where the actual *thinking* happens. The framework models everything around inference but not inference itself. Is that the right boundary? Or should inference be modeled as a scoped computation too — one that reads from the token window and produces proposals?

- Subagent conversations are nested turn loops. How deep can this nest? Is there a recursive structure? A subagent can spawn sub-subagents, each with their own turn loop, scope, and permission inheritance. This is recursive process creation — more π-calculus territory.
