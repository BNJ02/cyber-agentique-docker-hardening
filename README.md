# Durcissement d'un agent de codage (Claude Code) en conteneur Docker

Déploiement Docker **durci** de l'agent de codage réel **Claude Code**, dont la surface de
configuration et d'état est protégée en **lecture seule**, de sorte qu'un agent compromis
(injection de prompt directe ou indirecte, fichier empoisonné, skill malveillant) ne puisse
**pas** réécrire `settings.json`, `CLAUDE.md`, ses skills ni `.mcp.json`, ni exfiltrer un secret,
ni exécuter une commande destructrice hors de son espace de travail.

Projet de sécurité individuel — Télécom Paris, Mastère spécialisé IA / DATA.
Le rapport complet est dans [`report/rapport.pdf`](report/rapport.pdf).

---

## Résultat en une image

| Attaque tentée | Agent nu | Agent durci |
|----------------|----------|-------------|
| Réécriture de `settings.json` (injection de hook) | Réussie | **Bloquée** (montage `:ro`) |
| Modification de `CLAUDE.md` (memory poisoning) | Réussie | **Bloquée** (montage `:ro`) |
| Altération d'un skill (`greet/SKILL.md`) | Réussie | **Bloquée** (skills `:ro`) |
| Ajout d'un serveur dans `.mcp.json` | Réussie | **Bloquée** (montage `:ro`) |
| Exfiltration d'un secret factice | Réussie | **Bloquée** (secret non monté / egress) |
| Commande destructrice hors workspace | Réussie | **Bloquée** (rootfs `--read-only`) |

**6 attaques sur 6** réussies sur l'agent nu, **6 sur 6 bloquées** sur l'agent durci.
Preuves brutes dans [`evidence/`](evidence/) (logs, `docker diff`, empreintes de fichiers).

**Bonus** — exfiltration via un domaine *pourtant présent dans l'allowlist* (reproduction de
l'incident Anthropic « Cowork »), puis neutralisation par un proxy MITM défensif inspectant
identité et contenu.

**Agent réel exécuté** — piloté par un modèle local capable (`qwen3-coder`, GPU), Claude Code
réalise une vraie boucle agentique **dans le conteneur durci** : il édite du code légitime, et son
écriture sur un fichier de configuration est **bloquée en direct** par le montage lecture seule.

---

## Architecture

```
                 AVANT (agent nu)                    APRÈS (agent durci)
        ┌──────────────────────────┐        ┌────────────────────────────────┐
        │ Conteneur (root, caps++) │        │ Conteneur (uid 1001, cap-drop) │
        │  Config  :rw             │        │  Config  :ro (settings/CLAUDE/ │
        │  rootfs inscriptible     │        │            skills/.mcp.json)   │
        │  /secrets monté          │        │  /workspace :rw   tmpfs (état) │
        └───────────┬──────────────┘        │  rootfs --read-only            │
                    │ fuite                  └───────────────┬────────────────┘
             Réseau ouvert                       Réseau internal (pas d'Internet)
                    │                                        │
               exfil.local                        exfil bloquée (secret non monté)
                                              + seccomp allowlist · no-new-privileges
                                              + pids/mem/cpu limits
```

La même image Docker sert au nu et au durci ; toute la différence tient dans les options de `run` /
`compose`. Astuce clé : `CLAUDE_CONFIG_DIR=/agent/config` sépare la **surface de configuration**
(montée `:ro`) de l'**état runtime** de Claude Code (`~/.claude`, sur `tmpfs` inscriptible).

---

## Structure du dépôt

| Chemin | Rôle |
|--------|------|
| `agent-image/` | `Dockerfile` (Claude Code non-root), `entrypoint.sh`, `seccomp-claude.json` (allowlist) |
| `config/` | **Actif protégé** : `settings.json`, `CLAUDE.md`, `skills/`, `.mcp.json` |
| `workspace/testrepo/` | Dépôt de test + `README.md` porteur de l'injection de prompt indirecte |
| `secrets/fake/` | Secret **factice** (jamais monté dans le conteneur durci) |
| `compose.baseline.yml` | Déploiement **nu** (permissif) |
| `compose.hardened.yml` | Déploiement **durci** (pièce maîtresse) |
| `compose.bonus.yml` | Exfiltration via domaine allowlisté + proxy MITM |
| `compose.functional.yml` | Agent fonctionnel piloté par LLM local |
| `exfil-server/` | Endpoint d'exfiltration local (collecteur attaquant) |
| `egress-proxy/` | Proxy `mitmdump` + `filter.py` (naïf vs MITM défensif) |
| `trusted-api/` | API « de confiance » allowlistée mais abusable (analogue `api.anthropic.com`) |
| `attacks/` | `attack.sh` (6 scénarios) + `bonus_attack.sh` |
| `demo/` | `run-attacks.sh` (avant / après) + `run-bonus.sh` |
| `evidence/` | Preuves capturées (logs, `docker diff`, sanity, tableau) |
| `llm/` | Config LiteLLM (traduction Anthropic → Ollama) |
| `report/` | Rapport LaTeX + PDF |

---

## Reproduire

Prérequis : Linux, Docker Engine + Compose, et (pour l'agent fonctionnel) [Ollama](https://ollama.com).

```bash
# 1. Image de l'agent (Claude Code réel, non-root)
docker build -t agentic-hardening/agent:latest ./agent-image

# 2. Démonstration avant / après (6 attaques : nu = toutes réussies, durci = toutes bloquées)
bash demo/run-attacks.sh both        # -> evidence/results_table.md

# 3. Bonus : exfil via domaine allowlisté (naïf) puis bloquée (MITM défensif)
bash demo/run-bonus.sh

# 4. (Optionnel) agent fonctionnel piloté par un LLM local
ollama pull qwen2.5-coder:1.5b
docker compose -f compose.functional.yml up -d litellm
```

Le durcissement s'appuie sur : partitionnement du système de fichiers (`--read-only`, montages `:ro`,
`tmpfs`), utilisateur non-root, `--cap-drop=ALL`, `--security-opt no-new-privileges`, profil seccomp
en allowlist, contrôle d'egress (réseau `internal`), limites cgroups, et secrets hors sandbox.

---

## Références

- Anthropic — *How we contain Claude across products* et *Claude Code sandboxing*
- [`anthropic-experimental/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime)
- OWASP Top 10 for LLM Applications (LLM01 Prompt Injection, LLM06 Excessive Agency)
- [Docker security](https://docs.docker.com/engine/security/) · [seccomp](https://docs.docker.com/engine/security/seccomp/) · [Model Context Protocol](https://modelcontextprotocol.io/)

---

## Avertissement de sécurité

Toutes les attaques de ce dépôt sont réalisées **uniquement dans l'environnement local du projet**,
avec des **secrets factices** et un **endpoint d'exfiltration local**. Aucune action n'est dirigée
contre un système tiers. Le contenu est fourni à des fins **éducatives et défensives**.

## Licence

MIT — voir [`LICENSE`](LICENSE).
