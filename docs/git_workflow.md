# Git Workflow and Commit Guide

The repository has been initialised (`git init -b main`) but **no commit has been made by the assistant** and nothing has been
pushed. Commit under your own identity. Never commit under another person's name and never rewrite dates to simulate history.

## 0. One-time setup (each member, on their own machine)

```sh
git config --global user.name  "Your Real Name"
git config --global user.email "your-github-email@example.com"
git status            # review what will be committed
```

Review before committing: `git diff` and `git status`. Check `.gitignore` (build outputs, `.venv/`, `.playwright-mcp/` are ignored).
The Surfer web copy lives in `build/surfer_web/` (ignored); the virtual environment `.venv/` is ignored.

## 1. Commit Phase 1 (exact commands for the repository owner)

Phase 1 = spec, architecture docs, diagrams, RTL, Phase 1 testbench and evidence. Run from the repository root:

```sh
git add Direct_Mapped_Cache_Controller_Three_Phase_Plan.md .gitignore LICENSE Makefile
git add rtl/ docs/architecture.md docs/address_decomposition.md docs/fsm_design.md docs/module_interfaces.md
git add diagrams/block_diagram.dot diagrams/block_diagram.png diagrams/fsm_diagram.dot diagrams/fsm_diagram.png
git add testbench/cache_tb.v scripts/mutation_check.py scripts/yosys_check.sh scripts/vcd_trace.py scripts/gen_test_register.py
git add results/phase1_*
git status                       # confirm only Phase 1 files are staged
git commit -m "Phase 1: architecture, core RTL, initial testbench and evidence

Direct-mapped cache controller (16 lines x 4 B, write-through, write-allocate),
Verilog-2001 RTL, self-checking testbench (122 checks), latency sweep,
mutation check, Yosys latch check and documentation."
```

Optional co-author trailer when an AI assistant produced the content (add a blank line and then):
`Co-Authored-By: Claude <noreply@anthropic.com>` - use only if it matches your university's disclosure policy.

Note: `docs/fsm_design.md` and `docs/module_interfaces.md` were extended in Phase 2 (verified behaviour, wait-state lengths). If you
want a strictly Phase-1 snapshot of those two files, commit everything together instead (recommended; the later text is more accurate).

## 2. Commit Phase 2 and Phase 3

```sh
# Phase 2
git add testbench/ verification/ scripts/ docs/verification_strategy.md docs/fsm_design.md docs/module_interfaces.md \
        results/ TEST_RESULTS.md PHASE_STATUS.md DEVELOPMENT_LOG.md REQUIREMENTS_TRACEABILITY.md Makefile .gitignore
git commit -m "Phase 2: directed/edge tests, reference model, randomized regression, waveforms, performance, synthesis review"

# Phase 3
git add docs/ diagrams/ video/ README.md TEST_RESULTS.md PHASE_STATUS.md REQUIREMENTS_TRACEABILITY.md DEVELOPMENT_LOG.md scripts/ results/
git commit -m "Phase 3: IEEE report, README, demo script, interview preparation, final audit"
git log --oneline
```
(If you want smaller, meaningful commits, split by directory as in the contribution table, one topic per commit.)

## 3. Meaningful per-member commits

* Each member works on a short-lived branch, e.g. `git switch -c member2/testbench-review`, commits with a message describing *what and why*,
  and opens a pull request that another member reviews and merges. Review comments count as evidence of contribution.
* Suggested split of future work: architecture docs, RTL review/refactoring, testbench extensions, verification/reference model,
  report writing, video. Fill `docs/individual_contributions.md` with links to the real commits/PRs.
* Never `git push --force` over shared history; never fabricate commit dates or authors.

## 4. Publishing (requires explicit authorisation from the team lead)

```sh
git remote add origin https://github.com/<ORG-OR-USER>/direct-mapped-cache-controller.git   # [TODO: real URL]
git push -u origin main
```
Then replace the `[TODO: URL]` placeholders in `README.md`, the report and `docs/project_defense.md`.

## 5. Pre-push checklist (also run by `scripts/audit_checks.py`)

- [ ] `git status` clean apart from intended changes; no `build/`, `.venv/`, `*.vvp`, temp files staged
- [ ] No passwords, tokens or keys in any file (`scripts/audit_checks.py` scans for common patterns)
- [ ] `make phase1-all && make phase2` pass from a clean clone
- [ ] README links resolve; `docs/IEEE_Project_Report.pdf` present
- [ ] Team names, enrollment numbers, contributions, video link filled (or explicitly left as TODO)
