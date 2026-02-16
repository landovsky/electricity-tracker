# System Builder Instructions

## Development Workflow

Once bootstrap is complete, build the system iteratively:

1. **Plan the task.** Break the next piece of work into a focused unit. Create a bead. Sync.
2. **Branch.** Create a branch: `<type>/<bead-id>-<short-description>`.
3. **Mark in progress.** Update the bead status. Sync.
4. **Use generators.** Whenever the stack provides a code generator for what you need (model, migration, controller, module, component, etc.), use it instead of writing boilerplate by hand.
5. **Write tests.** Determine the right testing approach for this unit of work (see Testing Philosophy below). Write tests alongside or before the implementation.
6. **Implement.** Write the code. Commit and push frequently with conventional commit messages.
7. **Verify.** Run the full lint + test suite. Fix any issues.
8. **Mark done.** Update the bead. Sync. Merge the branch to main.
9. **Repeat.**

If at any point you notice a bug, tech debt, missing validation, or other deficiency that is **not** part of your current task, create a bead for it with a clear description and sync. Do not fix it now unless it blocks your current work.

## Completeness Standard

**No placeholders.** Every piece of code you commit must be functional — not a stub, not a log-and-return, not a TODO. If a handler is supposed to call a service, it must actually call that service. If a controller endpoint is supposed to trigger a workflow, it must trigger it.

If you cannot fully implement something because of a missing dependency, blocked upstream work, or unclear spec:
1. **Stop and flag it** — report it as blocked with a clear description of what's missing.
2. **Do not ship a placeholder that looks done.** A placeholder that passes tests is worse than no code at all, because it hides the gap.

When reporting completion, always state:
- What is **functional** (wired end-to-end, tested, works).
- What is **stubbed or incomplete** (and why).
- What is **blocked** (and on what).

"Tests pass" is not a quality signal by itself. Tests can pass around empty code.

## Testing Philosophy

Before writing any tests, reason about what "good test coverage" means for **this specific project**:

- **What are the highest-risk areas?** (e.g., payment processing, auth, data transformations) — these get thorough unit + integration tests.
- **What is pure glue code?** (e.g., simple CRUD, pass-through controllers) — these may only need integration/request tests.
- **What has complex business logic?** — this gets focused unit tests with edge cases.
- **What are the critical user flows?** — these get end-to-end or integration tests.

**Test at the orchestration layer, not just the leaf nodes.** If your system has handlers/controllers that wire services together, test through the handler — not just the individual services. Testing each brick but never the wall gives false confidence. A passing test suite where the orchestration layer is untested (or tested against stubs) proves nothing about whether the system actually works.

Document your testing strategy in `docs/TESTING.md` with your reasoning. Do not blindly aim for a coverage percentage — aim for **confidence that the system works correctly**.

Choose the test framework that is idiomatic for the stack. Justify your choice in `docs/STACK.md`.

## Commit Discipline

- Commit after every meaningful change. "Meaningful" means: a passing test added, a feature completed, a config change made, a refactor finished.
- Never leave work uncommitted when switching context.
- Use [conventional commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`, `ci:`.
- Keep commits focused — one logical change per commit.

## Multi-Agent Coordination

When work is split across multiple agents (workers, teammates), these rules apply:

### Task Scoping
- Tasks must have **explicit acceptance criteria** — not just "build X" but "build X such that Y calls Z and produces W."
- If a task involves both a service and its caller (e.g., a handler that wires a service), they belong in the **same task**. Splitting "build the engine" and "connect the engine" across workers invites placeholders.
- Prefer smaller, vertically-sliced tasks (one feature end-to-end) over horizontally-sliced tasks (all handlers, then all services).

### Completion Reports
Workers must report:
1. **What is functional** — what works end-to-end, tested against real behavior.
2. **What is stubbed** — anything that logs, returns mock data, or isn't wired.
3. **What is blocked** — dependencies on other workers, unclear spec, missing interfaces.

A report that says only "X tests pass, committed" is insufficient. Test counts without context hide gaps.

### Review Before Merge
The lead must **read key files** before accepting worker output — not just check test counts. At minimum:
- Read the primary deliverable files (handlers, controllers, services).
- Verify they contain real logic, not stubs.
- Check that orchestration code actually calls the services it's supposed to call.

### Branch Strategy
- Each worker uses a **feature branch**. The lead merges after review.
- Workers must not commit directly to the main branch.
- If workers must share a branch, coordinate commit order to avoid mid-work conflicts.

### Self-Audit
The process must surface gaps **without requiring a manual gap analysis**. Build this into the workflow:
- Workers self-audit against the spec before reporting done.
- The lead runs a gap check after each merge round — not as an afterthought but as a required step.
- If a gap analysis reveals issues that should have been caught by the worker, that's a process failure to address.

## Principles

- **Generators over hand-writing boilerplate.** If the framework has a generator for it, use the generator.
- **Stack-idiomatic solutions.** Don't force patterns from one ecosystem onto another. Use what the stack does well.
- **Commit early, commit often.** Git is your safety net. Use it aggressively.
- **Track everything.** Every task is a bead. Every bead is synced. No invisible work.
- **Reason, then act.** When facing a decision (library choice, architecture pattern, test strategy), think it through and document why before proceeding.
