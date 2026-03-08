# The *Ma* of Multi-Agent Systems

*A series on what programming language theory, Japanese aesthetics, and a late-night conversation about SQL macros reveal about the architecture of AI agent systems.*

---

Every multi-agent system has to answer the same questions: What does each agent see? How do agents hand off work? What happens when an agent needs something it wasn't given? How does the system improve over time?

These feel like new problems. They're not. Programming language theory solved the structural versions decades ago — closures, continuations, scoped visibility, monadic effects. The agent architecture community is rediscovering these ideas empirically, one framework at a time, without the shared vocabulary that would let them draw on what already exists.

That's the starting observation. But it's not the interesting part.

The interesting part is what happens when you take the correspondence seriously and push it. Not as metaphor — as structure. When you formalize what "an agent's scope" actually means, when you model how scopes change during execution, when you track what's visible and what's hidden across every participant in a conversation, you find something unexpected:

**The hidden part is the load-bearing part.**

In Japanese aesthetics, 間 (*ma*) is the concept that the space between things is itself functional. The pause that gives the notes shape. The empty room that makes the architecture. The negative space that tells you where to look. *Ma* isn't absence — it's the structural element that makes everything around it work.

Agent architectures have *ma*. Every scoping decision creates two things: what an agent can see, and what it can't. The tool-selection agent doesn't see the worker's line-by-line analysis — and that's *why* it can think clearly about tool selection. The worker doesn't see the selection rationale — and that's *why* it can focus on the code. The exclusions aren't limitations. They're the negative space that makes each agent's scope useful.

But *ma* goes deeper than scoping.

When a language model performs inference, the internal process — attention, sampling, chain of thought — is invisible to every other participant. When a human user reads the output and decides what to type next, their thinking is equally invisible. Both are doing the same thing: reading a scoped view of the conversation, performing an opaque internal process, and producing a lossy projection of their internal state as output. The model's hidden inference and the human's hidden thinking are structurally identical. They differ in degree — how much is hidden, how much context is inaccessible — but not in kind.

This turns out to be the axis that matters. Not "agent vs. tool" or "human vs. AI" — but *how much of the computation is opaque*. How much *ma* does each participant have?

A tool reading a file has borrowed *ma* — the filesystem is hidden from the conversation, but the tool itself is transparent. A deterministic orchestrator has minimal *ma* — its rules are knowable, its state is inspectable. A language model has intrinsic *ma* — the inference process itself is the source of opacity. A human has constitutive *ma* — you can't separate the person from their hidden state without destroying what makes them who they are.

And here's the punchline: **the amount of *ma* determines the role**. You put the low-*ma* actor at the center of the system because you need the hub to be predictable. You put the high-*ma* actor at the authorization boundary because only it can make judgment calls from inaccessible context. You constrain the medium-*ma* actor to proposing rather than deciding, because its inference is powerful but bounded. The architecture of a multi-agent conversation isn't arbitrary. It falls out of the opacity structure.

This series develops that idea in four parts.

**Part 1: Conversations Are Closures.** The structural correspondence between programming language closures and multi-agent conversation architecture. Scope, capture lists, continuation passing, and why every agent framework is implementing closures whether it knows it or not. Where the correspondence holds, where it breaks, and what the breakdowns reveal.

**Part 2: The Anatomy of a Turn.** What actually happens in a conversation turn — concretely, grounded in how systems like Claude Code work. The four kinds of actors (Principals, Inferencers, Executors, and the orchestrating system). Permission negotiation as a protocol. Parallel tool execution. Backgrounded tasks as promises. The orchestrator as the most powerful and least understood participant.

**Part 3: The Space Between.** *Ma* as the organizing principle. Why every actor has hidden state, why the *kind* of hidden state determines the actor's natural role, and why the conversation's architecture is a consequence of its opacity structure. The shared read → infer → respond process that humans and language models have in common, and what that means for how we design agent systems.

**Part 4: Toward a Formal Framework.** Parameterized monads for scope transitions. The π-calculus for concurrent agents and scope extrusion. Session types for permission protocols. What survives formalization, what doesn't, and where the open problems are. A honest accounting of what's novel and what's Moggi (1991) with better marketing.

---

This work grew out of building [Fledgling](https://github.com/teaguesterling/fledgling), a SQL-based code intelligence toolkit for AI agents. The practical questions — what should an agent see? how do tools compose? what context matters? — led to the structural observations. The structural observations led to the formal framework. The formal framework led to *ma*.

The conversation itself was the proof of concept: two participants with asymmetric visibility over a shared log, passing continuations back and forth, generating ideas that could only exist within the context that produced them. A sixteen-year-old dog who doesn't like her meds was involved. Whiskey was present.

Sometimes the most interesting things happen at wide context windows.

---

*Next: [Part 1 — Conversations Are Closures →](conversations-as-closures.md)*
