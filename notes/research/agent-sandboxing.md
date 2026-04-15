# Agent Sandboxing — Research Notes

**Date:** 2026-04-14  
**Status:** Research only — production box concern, not needed for home setup PoC

---

## Why Sandboxing Matters for This Project

When AI agents (Continue.dev Agent mode, Claude Code, etc.) write and execute code autonomously,
they have access to your filesystem, credentials, and network. Without a sandbox, an agent can:

- Read files outside the project (credentials, config files)
- Make unexpected outbound network calls
- Route inference to external cloud APIs instead of your local vLLM
- Execute arbitrary code on your host system

Sandboxing puts a hard boundary between the agent and everything else. It's the same concept
used in browsers (each tab is sandboxed), app stores, and OS security — just applied to AI agents.

There are two distinct types of sandboxes relevant to us:

---

## Type 1 — Agent Governance Runtime

Controls *what the agent is allowed to do*: file access, network calls, which inference backend
it talks to. A policy layer.

### NVIDIA OpenShell
**Repo:** https://github.com/NVIDIA/OpenShell  
**License:** Apache 2.0  
**Status:** Alpha (announced GTC 2026)

OpenShell is the governance layer between the agent and your infrastructure. It enforces
declarative YAML policies that control:

- **Filesystem access** — agent can only read/write explicitly allowed paths
- **Network policy** — blocks unauthorized outbound connections
- **Privacy router** — forces all inference calls to your local vLLM instead of cloud APIs
- **Process isolation** — prevents privilege escalation

Policies are enforced *out-of-process* — the agent cannot override them even if compromised.

**Why it's relevant for us:** The privacy router is a direct fit for our "fully private, no cloud"
requirement. It ensures Continue.dev or any other agent always hits our local LiteLLM endpoint
and can never silently route to OpenAI.

**Architecture with OpenShell:**
```
Developer
    │
    ▼
OpenShell sandbox (policy enforcement)
    │
    ▼
Continue.dev / Claude Code
    │
    ▼
LiteLLM (port 4000)  ← privacy router ensures this is always used
    │
    ▼
vLLM → production GPU
```

**Installation (when ready):**
```bash
# Install CLI
curl -fsSL https://openshell.nvidia.com/install.sh | sh

# Create a sandbox for a coding agent
openshell sandbox create -- claude   # or: opencode, codex, copilot

# With GPU passthrough (experimental)
openshell sandbox create --gpu -- claude
```

**Caveats:** Alpha software. Single-developer mode only right now. Multi-tenant enterprise
support is on the roadmap. Do not use in production yet.

---

## Type 2 — Code Execution Sandbox

Isolates *the code the agent runs*. When an agent writes a Python script and executes it,
these prevent that script from escaping to the host. Uses microVMs or user-space kernel
interception — regular Docker containers are not sufficient (they share the host kernel).

### Daytona
**Repo:** https://github.com/daytonaio/daytona  
**License:** Apache 2.0  
**Status:** Production-ready, self-hostable

Daytona is the strongest self-hosted option. Relevant features for us:

- Open source, runs on your own infrastructure
- Sub-90ms sandbox creation
- Native Git integration and LSP support (language servers work inside the sandbox)
- GPU support
- Docker-in-Docker capability

**Why it's relevant for us:** When developers run agent-generated code on the production box,
Daytona ensures that code can't touch the host system, other developers' environments, or
internal services it shouldn't reach.

**Basic setup:**
```bash
# Install
curl -fsSL https://get.daytona.io | bash

# Start the server
daytona server

# Create a sandbox workspace
daytona create --git-url https://github.com/your-org/your-repo
```

### E2B (for comparison)
**Site:** https://e2b.dev  
**License:** Open source core, managed cloud  

E2B has the best developer SDK experience and is widely used in the AI community. However,
self-hosting is experimental and cloud sessions are capped at 24 hours. Better suited for
teams that don't need full on-prem control.

---

## Recommended Approach for Production Box

Use **both layers** — they solve different problems:

1. **OpenShell** — governance layer. Controls where inference goes, what files agents can touch,
   what network calls they can make. One OpenShell gateway per team or per environment.

2. **Daytona** — execution layer. Isolates code the agent actually runs. One sandbox per
   developer session or per task.

```
OpenShell (governance)
    └── Daytona sandbox (execution)
            └── agent runs code here safely
```

Neither is needed for the home PoC — both are production box concerns. Add to the migration
checklist when the DGX Spark arrives.

---

## Further Reading
- OpenShell docs: https://docs.nvidia.com/openshell/latest/index.html
- Daytona docs: https://www.daytona.io/docs
- E2B docs: https://e2b.dev/docs