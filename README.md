# Evo

A self-evolving Elixir application that uses Claude's API to iteratively improve its own code. Runs on a Raspberry Pi 5 with Phoenix 1.8, SQLite3, and a real-time LiveView dashboard.

## How It Works

Evo runs a continuous evolution loop that proposes, validates, and applies code changes to itself:

1. **Benchmark** — Measure the current performance of a target module (execution time, memory, code size)
2. **Propose** — Send the module source + benchmarks to Claude, requesting one focused improvement
3. **Validate** — Run a 5-gate safety pipeline: size limits, AST allowlist, side-effect detection, compilation check, and test suite
4. **Apply** — Write the new code to disk and hot-reload the module
5. **Evaluate** — Re-benchmark and compare fitness (60% time, 30% memory, 10% code size). Rollback if regressed
6. **Record** — Persist the generation to SQLite and git commit the change

## The Evolvable Surface

Only three modules are allowed to be modified by the system — the code that controls how it evolves:

| Module | Role |
|---|---|
| `Evo.Evolvable.PromptBuilder` | Constructs the prompt sent to Claude |
| `Evo.Evolvable.Fitness` | Evaluates before/after benchmark fitness |
| `Evo.Evolvable.Strategy` | Selects which module to evolve next (round-robin) |

The Validator enforces an allowlist-based AST walk and the Applier has a hardcoded file whitelist — no other modules or paths can be written to.

## Architecture

```
Evo.Evolver          GenServer orchestrating the evolution loop
Evo.Benchmarker      Microbenchmark runner (:timer.tc, 100 iterations)
Evo.Proposer         Claude API caller + response parser (via Req)
Evo.Validator        5-gate safety pipeline (AST allowlist, compilation, tests)
Evo.Applier          File writer + hot code reload (:code.purge/compile_file)
Evo.Historian        SQLite persistence + git committer
Evo.ModelRouter      Haiku/Sonnet cost optimization (escalates after 3 failures)
Evo.TokenBudget      Daily token budget tracking (resets at UTC midnight)
```

## Observability

A LiveView dashboard at `/evolution` shows:

- Generation count, accept rate, current model, budget usage
- Model routing stats (Haiku/Sonnet calls, escalation count)
- Token budget progress bar with daily and lifetime totals
- Generation history table with status badges, fitness scores, and reasoning

Phoenix LiveDashboard is available at `/dev/dashboard` in development.

## Setup

```bash
mix setup
mix phx.server
```

Requires the `ANTHROPIC_API_KEY` environment variable. The evolution loop starts paused — trigger it manually from the dashboard or via `Evo.Evolver.run_once()` in IEx.

## Configuration

| Env Var | Purpose | Default |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude API key | (required) |
| `EVO_DASHBOARD_USER` | Dashboard basic auth user | `evo` |
| `EVO_DASHBOARD_PASS` | Dashboard basic auth password | `changeme` |
| `DATABASE_PATH` | SQLite database path (prod) | `evo_dev.db` / `evo_test.db` |
