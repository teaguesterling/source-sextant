# Conversations Are Closures: A Programming Language Framework for Multi-Agent Architecture

*Or: how sixty years of PL theory already solved the agent orchestration problem*

---

You're building a multi-agent system. You need to decide: what context does each agent see? How do agents hand off work? How does the system learn from past interactions? What happens when an agent needs something it wasn't given?

These feel like new problems. They're not. Programming language theory solved the structural versions of all of them decades ago. We just haven't noticed they're the same problems.

## The observation

Here's what a multi-agent conversation looks like in practice:

A primary agent receives a task. It delegates to a subagent, passing along some context — maybe a task description, some relevant files, a set of tools. The subagent works, produces results, and hands them back. Maybe the subagent delegates further. At each handoff, someone decides what context flows forward and what gets left behind.

Now here's what a closure looks like:

A closure is a function bundled with the variables it captured from its surrounding scope. When it executes, it can see those captured variables but not the rest of the environment. It produces a result that becomes available to whoever called it. Closures can nest — an inner closure captures from an outer closure's scope.

These aren't just analogous. They're the same structural pattern.

## The mapping

| Programming Language Concept | Multi-Agent Architecture |
|---|---|
| Shared heap | The full conversation log (append-only) |
| Lexical scope | Visibility rules for each agent |
| Closure | An agent + the context it can see |
| Capture list | What context an agent receives at spawn |
| Continuation passing | Handing the conversation to the next agent |
| Activation frame | An agent's current working window |

Multiple agents operate on a single, growing conversation log. Each agent is a closure: it captures a scoped subset of the log, operates within that scope, adds new state, and passes the whole log forward. The next agent closes over a different subset of the now-larger log.

The conversation is the shared heap. Each agent's visibility is its lexical scope. The handoff between agents is continuation passing.

### A concrete example

A user asks a primary agent to "review the auth module for security issues." Here's what happens, and its closure equivalent:

1. **The primary agent** appends the task to the conversation log and delegates. In closure terms, it creates a new closure whose capture list includes the task description and the file paths, but not the primary agent's other ongoing work.

2. **A tool-selection agent** (the "quartermaster") receives that scoped view. It queries past sessions — "what tools were useful for security reviews?" — and assembles a kit: a static analysis tool, a dependency checker, the module's recent git history. It appends this kit to the log and hands off. In closure terms, it captured the task and tool history, produced new bindings (the kit), and passed a continuation: "here's the scope for the worker, resume with these tools."

3. **The worker agent** receives a closure over the task, the kit, and the code — but not the quartermaster's selection rationale or the primary agent's broader context. It does the review, appends findings to the log, and returns.

Each agent saw a different slice of the same growing log. The scoping was the architecture. The correspondence isn't exact — a real closure's capture list is fixed at creation, while an agent's scope can be renegotiated mid-task (as when the worker requests a new tool). But the structural pattern is close enough to be a useful design guide, and the places where it breaks down are themselves informative.

## Why this framing matters

This correspondence isn't just a cute analogy. It's a design framework that gives concrete answers to questions the agent community is currently solving ad hoc.

### "What should a subagent see?"

This is the capture list question. When you spawn a closure, you decide which variables it captures from the enclosing scope. When you spawn a subagent, you decide which conversation history, tools, and context it receives.

Every multi-agent framework has a version of this. OpenAI's Agents SDK has `include_contents` parameters on handoffs. Google's context-aware framework treats context as a "compiled view over a richer stateful system." LangChain lets you scope what a callee sees.

They're all implementing capture lists. The closure framing makes this explicit: you're not "configuring context" — you're defining a scope.

### "How do agents share state?"

They don't share mutable state. They close over a shared, append-only log. Each agent reads from its scope and appends to the log. No coordination protocols, no locking, no race conditions. This is the same insight that makes persistent data structures and event sourcing work: if the log only grows, concurrent readers can't interfere with each other.

Recent event-sourcing approaches to agent architecture arrive at exactly this model — agents emit structured intentions, a deterministic orchestrator persists events in an append-only log, and downstream agents read materialized views. They frame it as event sourcing. We're framing it as closure semantics. Same structure, different vocabulary.

### "What happens when an agent gets stuck?"

In the traditional call-stack model, a stuck subagent fails, the error propagates up, the parent re-evaluates, and maybe retries with different parameters. Context is lost. Work is repeated.

In the closure/continuation model, a stuck agent doesn't fail. It passes a continuation: "Here's my state, here's what I need, resume me when you can provide it." The handler (what we've been calling the "quartermaster" — more on that below) fulfills the request and the agent continues from where it left off. No unwinding, no lost context, no re-derivation.

This is literally continuation passing style (CPS) from PL theory, applied to agent orchestration. The conversation log preserves the agent's full state. The continuation is a request for resources plus a pointer to where to resume.

### "How does the system improve over time?"

Query the log. The conversation log isn't just state — it's training data. Past closures' contributions (which tools were used, which were requested but missing, how many steps each task took) inform how future agents are scoped.

This closes a learning loop that most frameworks leave open: the system doesn't just execute tasks, it accumulates evidence about what works. A "quartermaster" agent can query past sessions to assemble better tool kits for future workers — not reasoning from first principles each time, but drawing on what actually worked before.

## The quartermaster pattern

The closure framing doesn't just describe existing systems — it suggests a natural architecture. In our work on tool-equipped code intelligence agents, we kept finding the same three roles emerging:

**The primary agent** knows the goal. It operates at the level of intent — "refactor the auth module," "review this pull request."

**The quartermaster** knows the tools and their history. It doesn't do the work — it assembles the right kit for the job. It reads the task description, queries past sessions for what tools were effective on similar tasks, and constructs a capture list: here are your tools, here's your initial context, here's your scope.

**The worker agent** knows the craft. It receives a scoped view of the conversation (its closure), does the work using the tools it was given, and adds its findings to the log.

The quartermaster's scope includes tool performance history and task patterns but not the worker's line-by-line analysis. The worker's scope includes the immediate code context and its assigned tools but not the quartermaster's selection rationale. The primary agent sees the task and the final result but not the intermediate steps.

They're all operating on the same growing log with different visibility. Three closures over one heap.

And critically: when the worker needs a tool it wasn't given, it doesn't fail. It passes a continuation to the quartermaster — "I need the dependency graph, here's why, here's my current state." The quartermaster fulfills the request, and the worker resumes. The quartermaster notes the gap for next time. The system learns.

This pattern isn't hypothetical. Every LLM client that manages a context window is already a quartermaster — it decides what tokens the model sees, what gets compacted when context runs low, which tools are loaded, how much budget remains. The human provides the goal. The client constructs the scope. The model works within it. Three participants, three scopes, one conversation. The quartermaster is the role we haven't named, not the role we haven't built.

## The conversation IS the program

Here's where it gets interesting.

A conversation log has a reflective property: it's simultaneously a record of what happened and an input that shapes what happens next. The log is both:
- **Data**: what happened, what was said, what tools were used
- **Program**: the evidence base for how to scope future agents, what tools to provide, what context matters

When the quartermaster reads past sessions to configure a new worker, the log is functioning as an input to a meta-level program. When the worker adds findings that future quartermasters will read, execution traces are becoming future inputs. The conversation is simultaneously the record of past behavior and a source of future behavior. This isn't homoiconicity in the strict sense — the log isn't a syntactically transformable program in its own language. But it's a form of reflection: the system can inspect its own execution history and adapt.

This is why pre-composed operations matter in this context. A named pattern like "find the most complex functions in recently changed files" isn't just a query — it's an encoded pattern of expert thinking, compressed into a reusable form. It captures a *way of looking at code* that can be applied without reconstructing the reasoning behind it.

The conversation log accumulates these patterns. Each successful task completion adds an example of "here's how this kind of problem was solved." Future agents close over these examples. The system's vocabulary grows.

## A practical implication

If the closure correspondence holds, it suggests what properties the meta-structure of agent communication benefits from. Not Lisp syntax — nobody's writing S-expressions in chat. But structural properties that make scoping explicit and composable:

- **Uniform representation**: messages, tool calls, context rules, and scoping annotations all in the same substrate
- **First-class agents**: composable, scopable units that can be nested and passed around
- **Pre-composed patterns**: encoded operations that transform conversation structure before agents process it
- **Reflective access**: agents can inspect the log that produced them

The content stays natural language. The plumbing — who sees what, how context flows, where continuations point — becomes formal. Not because formalism is inherently better, but because the problems it solves (scope safety, capture correctness, continuation semantics) are exactly the problems agent architects are struggling with today.

## The space between agents

Every scoping decision creates two things: what's visible and what's excluded. Programming language theory focuses on the capture list — what the closure can see. But there's a complementary tradition that focuses on the other half.

In Japanese aesthetics, 間 (*ma*) is the concept that the space between things is itself functional. The pause in music that gives the notes shape. The empty room that makes the architecture. The negative space in a painting that tells you where to look. *Ma* isn't absence — it's the structural element that makes everything around it work.

Agent architectures have *ma*. The quartermaster doesn't see the worker's line-by-line code analysis — and that's why the quartermaster can think clearly about tool selection. The worker doesn't see the quartermaster's historical queries — and that's why the worker can focus on the code in front of it. The primary agent doesn't see the intermediate steps — and that's why it can reason about the goal.

These exclusions aren't limitations. They're the negative space that makes each agent's scope useful. A closure that captured *everything* would be useless — it would be the entire heap with no focus. Scoping is as much about what you leave out as what you let in. The gap between agents is load-bearing.

This is why the capture list is a design decision, not a configuration detail. Every variable you exclude from a closure's scope is a decision about what that closure doesn't need to think about. Get it right and the agent works cleanly within its frame. Get it wrong — capture too little and it gets stuck, capture too much and it drowns in irrelevant context.

PL theory gives us the formal tools: capture lists, lexical scope, visibility rules. *Ma* gives us the design intuition: the empty space is not a gap to be filled. It's the thing that makes the structure work.

## What's already here, and what's missing

None of this is happening in a vacuum. Formal models of concurrent communicating agents have existed for decades. Hewitt's actor model (1973) describes agents with private state communicating via asynchronous messages — and Hewitt himself noted the connection between actors and closures. Milner's π-calculus formalizes scope extrusion: the ability to widen an agent's visibility at runtime, which is exactly what happens when a worker requests a new tool from the quartermaster. The BDI (belief-desire-intention) architecture has been formalizing agent internals since the 1990s.

These are rigorous frameworks. What we're proposing is not a replacement for them but a *lens* — a way to see the family resemblance across the specific design decisions that LLM-based agent frameworks are making today:

- **Append-only event logs**: event-sourcing approaches to agent state (Akka, CQRS patterns)
- **Scoped context visibility**: Google's compiled context views, OpenAI's handoff parameters
- **Continuation-style handoffs**: OpenAI Agents SDK, LangChain multi-agent delegation
- **Session analytics for optimization**: various framework-specific implementations

Each of these reinvents a piece of what closure semantics already describes. The individual solutions work. What's missing is the shared vocabulary that would let practitioners reason about all of them as instances of the same pattern — and draw on the decades of formal work that already exists on scope safety, capture semantics, and continuation behavior.

## The deeper implication

Once you see conversations as closures and closures as monadic contexts, something else comes into focus.

A pure function is deterministic. Given the same inputs, it always produces the same output. Nothing about the world is left unspecified — the inputs fully determine the output. One set of inputs, one possible world, one result.

Now raise the temperature. Literally — set an LLM's temperature above zero. Suddenly there's a distribution of possible outputs. The inputs no longer fully determine the result; sampling introduces unspecified choices. Same input, multiple possible worlds, weighted by how much you left to chance.

Add a conversation history. The context now includes everything that was said before — every previous closure's contribution, every accumulated decision. The number of possible worlds grows with every turn, because each participant's response depends on state the system can't fully observe.

Add a human. The context now includes the entire lived experience of a person — their expertise, their intuitions, their physical state, what happened at work, whether they slept well. The degree of underspecification is enormous. Most of what determines the output is invisible to the other participants.

But at every point on this spectrum, it's the same structure: a value generated within a context. A monad. The only thing that changes is how much of the world is left unspecified by the inputs — how many possible worlds are consistent with what you can observe.

This means determinism isn't a property of the computation. It's a property of how fully specified the inputs are. A function with no underspecification is deterministic. A function with unspecified context — randomness, user state, network conditions, the mood of the person asking — is non-deterministic. They're not different kinds of computation. They're the same kind with different degrees of openness to the world.

Moggi's insight (1991) was that computational effects — side effects, exceptions, nondeterminism, state — could all be modeled as monads, giving a uniform framework for reasoning about what a computation depends on beyond its explicit inputs. The Haskell community built on this directly. The `Maybe` monad: a context where values might not exist. The `IO` monad: a context where the outside world matters. The `List` monad: a context where multiple values are possible. Probability monads: a context where outcomes are weighted.

Not all monads fit the underspecification framing cleanly — `Writer` accumulates output, `State` threads mutable bindings, `Cont` reifies control flow. The spectrum isn't universal. But for the monads that model *what the computation can't see or control*, the pattern holds: each one handles a different degree of openness to the world outside the function's inputs.

This specific continuum — from fully determined to radically open — is well-trodden in adjacent fields. Modal logic formalizes possible worlds via accessibility relations. Algebraic effects model computational side channels. What we're suggesting is more modest than a new theory: it's that multi-agent conversations belong on this same spectrum, and that recognizing this lets practitioners borrow tools from PL theory instead of reinventing them. A deterministic function is a trivial point on the spectrum. A temperature-controlled LLM is a probability monad. A conversation is an `IO`-like monad with an append-only log. A human in a conversation is a participant whose inputs include the entire physical world.

The boundary between "programming" and "conversation" is not a boundary. It's a dial. And monads — specifically, Moggi's framework for computational effects — stay coherent across a surprisingly wide range of that dial.

If that's true, then agent orchestration frameworks don't need to invent new abstractions for context management, scoping, and handoffs. The abstractions exist. The formal tools exist. The opportunity is in connecting the communities that built them with the communities that need them.

## The punchline

Every multi-agent framework is implementing closures. Most don't know it yet.

The scoping decisions, the context management, the handoff protocols, the learning loops — they're all ad hoc implementations of concepts with rigorous foundations. Church gave us lambda calculus in the 1930s. Landin gave us closures in the 1960s. Hewitt gave us the actor model in the 1970s. Moggi gave us computational monads in the 1990s. The formal tools for reasoning about scoped, concurrent, communicating agents have existed for decades. The LLM agent community is rebuilding them from scratch, without the shared vocabulary that would let them draw on what's already known.

The invitation is simple: look at your agent architecture through the lens of closure semantics. The conversation is the heap. The agents are closures. The handoffs are continuations. The scoping rules are capture lists.

You already know how this works. You just didn't know you knew.

---

*This idea emerged from a late-night conversation about SQL macros, tool composition, and what it means for an AI agent to "reach for the right tool." It wound through carpenter metaphors, quartermaster patterns, and continuation passing before landing somewhere neither participant expected.*

*The conversation itself was the proof: two closures with asymmetric visibility over a shared log, passing continuations back and forth, generating values that could only exist within the context that produced them. A sixteen-year-old dog who doesn't like her meds was involved. A small chihuahua got some of the meats. Whiskey was present.*

*Sometimes the most interesting things happen at wide context windows.*
