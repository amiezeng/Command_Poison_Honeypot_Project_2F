# Design Proposal Draft

**Note for team:** Cover page, Project Planning, and Works Cited are omitted for now per team request. Paste into Word as Times New Roman, 12pt, double spaced. Figures and appendices do not count toward the page limit.

---

## Overview

Organizations spend significant time and money trying to understand how people and automated tools behave once they get into a system they should not be in. Traditional decoy systems often present a fixed, pre-built environment. Attackers who realize the environment is thin, empty, or unchanging may leave quickly, which limits what defenders can learn.

This project asks whether a decoy environment that *responds* to what an attacker is already doing can increase meaningful interaction. Both conditions start with the same small set of synthetic files. In the static condition, that environment never changes. In the dynamic condition, when the system detects broader patterns of interest—such as looking for credentials, backups, or application source code—it creates a limited number of additional fake files that fit those patterns. The new files contain only invented values and never real secrets.

The real-world impact is practical. If behavior-responsive decoys keep attackers exploring longer, security teams may collect richer logs about tools, tactics, and targets of interest. If they do not—especially when most traffic is automated and short—that is equally useful: it tells us that adaptation alone may not change bot-driven activity, and that resources are better spent elsewhere. Either outcome helps leaders decide whether adaptive decoy content is worth building.

This proposal reflects feedback from our design interview. We moved away from large language model–driven responses because of security, permission, consistency, and experimental-control concerns. Instead, we use a constrained, template-based approach with a clear hypothesis about engagement.

---

## Research Question

**Primary research question:**  
Does introducing a limited number of synthetic files in response to observed attacker behavior increase session length, number of commands executed, and number of files accessed, compared with an otherwise identical environment that never adds files after the session begins?

We deliberately frame the question around *behavior-responsive synthetic file generation*, not around the decoy platform itself. The platform is the measurement instrument; the scientific claim is about whether adaptation changes interaction.

### Definitions

**Attacker.** Any remote party that successfully authenticates to our SSH service over the public internet using the exposed credentials we intentionally provide. This includes automated bots and scripts as well as any human operators. We do not assume attackers are human unless session behavior clearly suggests otherwise. Based on expected traffic to university public addresses, we anticipate that most sessions will be automated and may execute relatively few commands.

**Synthetic artifact / synthetic file.** A file created for research purposes that looks like something an attacker might find valuable (for example, a fake configuration file, a fake credential dump, a fake database backup, or fake application notes) but contains only invented hostnames, usernames, keys, and data. No real credentials, secrets, or sensitive organizational information are ever placed in these files.

**Initial filesystem.** The fixed set of directories and files present at the start of every session in both conditions. Both conditions begin with the same initial filesystem.

**Static condition.** Sessions in which the filesystem does not change in response to attacker actions. Whatever files exist at session start remain the only files available for the duration of that session (aside from normal operating-system files already present on the image).

**Dynamic condition.** Sessions in which a rule-based behavior detector watches commands and file access patterns. When a recognized behavior category is detected, and if a per-session generation limit has not been reached, the system writes one additional synthetic file from a matching template family into a predictable location in the environment.

**Behavior category.** A broad class of activity inferred from command text and file paths, not a one-to-one rule for every possible command. For this study we use four categories:

1. Credential discovery (signals related to passwords, secrets, tokens, `.env`, `.ssh`, and similar).
2. Backup discovery (signals related to backups, archives, and versioned copies).
3. Source-code / application investigation (reading project or application files and related configuration).
4. System reconnaissance (basic host identity and process or network inspection commands).

Unrecognized activity is logged but does not trigger generation. That is acceptable: we are testing the effect of responding within a defined set of detectable behaviors, not claiming we can interpret every action.

**Engagement (primary dependent measures).**

1. **Session length** — time from successful SSH login to session end (logout, disconnect, or forced recycle).
2. **Command count** — number of commands executed during the session.
3. **Files accessed** — number of distinct files read, listed in detail, or otherwise opened by the attacker during the session.

Secondary measures (for interpretation, not primary hypothesis tests) include whether any generated file was accessed, time from generation to first access, and whether a later file was generated after an earlier generated file was investigated (“breadcrumb” following).

**Independent variable.** Environment type: static versus dynamic, randomly assigned when a decoy instance is brought online.

---

## Background

*[Citations to be added: at least three academic sources and one reputable non-academic source; include one closely related study. Placeholder narrative below states the claims those sources will support.]*

Prior work on decoy systems shows that interaction quality depends heavily on how believable and populated the environment appears. Empty or obviously fake systems tend to produce short, shallow sessions. That observation motivates our interest in engagement, but it also creates a methodological trap: simply adding more content can look like “success” even if adaptation itself does nothing. Our design therefore holds the starting environment constant and isolates *when* additional content appears.

Research on attacker behavior after initial access commonly describes stages such as reconnaissance, discovery of credentials or configuration, and further investigation of whatever those materials point to. Automated internet scanning against SSH, however, often produces brief, scripted sessions that do not resemble careful human exploration. That distinction matters for our study. If most visitors are bots that run a fixed sequence and leave, dynamic files may rarely be noticed. Interview feedback pushed us toward a constrained design for exactly this reason: we need a clear independent variable and a clear takeaway, not an open-ended system that tries to please every request.

A closely related line of work examines adaptive or interactive deception—systems that change responses based on attacker actions. Much of that work either focuses on network-level deception or on richer generative approaches. Our contribution is narrower. We do not claim to build a generally intelligent decoy. We test whether a small, rule-driven, template-based expansion of the filesystem, triggered by detectable behavior categories, changes measurable engagement relative to a static twin that starts with the same files.

Interview feedback also redirected us away from large language models. LLM-driven responses raise security and university-permission concerns, increase nondeterminism, and make it hard to know what was actually being tested. Reviewers asked what real-world conclusion we could draw if the system simply gave attackers “more than they asked for.” We therefore narrowed the mechanism: when a behavior category is detected, we may add one synthetic file from a fixed template family, up to a hard maximum per session. We do not invent arbitrary command outputs or unrestricted new worlds. Consistency is maintained by templates and shared fake identity values within a session (for example, a fake database name reused across related files).

Hard-coded scripts for every possible command are not practical; attackers have too many surface forms for the same intent. Behavior categories are our compromise between exhaustive scripting and unconstrained generation.

---

## Hypothesis

We pick a directional claim rather than a neutral “difference either way” stance, as recommended in our interview: we expect the dynamic condition to increase engagement on our primary metrics.

**Null hypothesis (H₀):**  
There is no difference between the static and dynamic conditions in mean session length, mean command count, or mean number of files accessed.

**Alternate hypothesis 1 (H₁ — session length):**  
Mean session length is greater in the dynamic condition than in the static condition.

**Alternate hypothesis 2 (H₂ — command count):**  
Mean number of commands executed per session is greater in the dynamic condition than in the static condition.

**Alternate hypothesis 3 (H₃ — files accessed):**  
Mean number of distinct files accessed per session is greater in the dynamic condition than in the static condition.

**Exploratory alternate (H₄ — breadcrumb follow-through):**  
Among dynamic sessions in which at least one synthetic file is generated, a non-trivial share of sessions will access at least one generated file. We treat this as exploratory because automated traffic may rarely reach generation thresholds.

We will test H₁–H₃ with appropriate statistical comparisons after applying pre-registered filters (for example, excluding empty failed logins and optionally analyzing a subset of sessions that exceed a minimum command count, given expected bot traffic). Failure to reject H₀ is a valid scientific outcome and would suggest that, under predominantly automated SSH probing, behavior-responsive file generation does not meaningfully change engagement.

---

## Limitations

Several limitations affect how strongly we can answer the research question.

**Attacker population.** Most traffic is expected to be automated. Bots often run short, fixed command sequences and may never notice a newly created file. That reduces the chance of observing the adaptation effect even if the mechanism works for humans. We address this by logging automation indicators where possible, reporting results for all sessions and for a higher-activity subset, and maintaining a backup research question if primary comparisons are uninformative.

**Incomplete behavior coverage.** We only respond to four behavior categories. Many actions will be logged without generating a file. That limits ecological “completeness” but protects experimental clarity. We cannot claim effects for behaviors we do not detect.

**Artifact volume confound.** Dynamic sessions can end with more files than static sessions. Greater engagement could then reflect “more things to look at” rather than the fact that files appeared in response to behavior. We mitigate this with a hard maximum number of generated artifacts per session (proposed cap: **three** additional files). We also report engagement metrics alongside the number of files available at session end, and we treat access to *generated* files as a secondary check that adaptation—not only volume—matters. A stronger future control would preload the static condition with the same total file set; we acknowledge that as a design improvement if early data show volume effects dominating.

**Template realism.** Template-based files may still look artificial to careful humans. Inconsistency across files could cause early exit. We reduce this risk with shared synthetic identity values within a session and small, curated template families. We are not using an LLM in the initial study.

**Fast recycle tradeoff.** Recycling virtual machines in seconds maximizes sample size but may cut off longer sessions and understate maximum engagement. We will define recycle triggers carefully (idle timeout, session end, and safety limits) and report how often sessions were truncated by recycle policy.

**Architecture limits.** High-interaction virtual machines increase operational risk relative to low-interaction emulators. Isolation, egress controls, and monitoring reduce but do not eliminate that risk. Random assignment of condition to instances improves balance over time but does not guarantee equal traffic volume on every calendar day.

**External validity.** Findings from university public IP space may not generalize to enterprise networks or to human red-team participants. Our takeaway will be scoped to internet-facing SSH decoys under similar traffic conditions.

---

## Honeypot Architecture

### Characteristics and framework

We deploy isolated Linux virtual machines reachable over SSH on assigned University of Maryland public IP addresses. Each live instance is randomly assigned to either the static or dynamic condition at bring-up. Assignment is independent per instance lifecycle; we are not fixing a permanent two-and-two IP split, and we are not using block randomization.

All instances share:

- the same base operating system image  
- the same initial filesystem and synthetic starter content  
- the same SSH entry configuration  
- the same logging pipeline  
- the same network security policy  

The only intentional difference is whether the behavior detector may write additional template-based synthetic files during the session, up to the per-session maximum.

**Suggested figure (does not count toward page limit):** a simple flowchart: Attacker → SSH on public IP → Isolated VM (static *or* dynamic) → Logger → (dynamic only) Behavior detector → Artifact generator → New synthetic file appears in guest filesystem → continued attacker activity → logs to central store / Slack alerts.

### Lifecycle and recycling

To maximize attack volume, instances recycle as quickly as practical—on the order of seconds after a session ends or after safety/idle triggers fire. The lifecycle is:

1. Boot a clean VM from the golden image (initial filesystem restored).  
2. Randomly assign static or dynamic.  
3. Expose SSH on the assigned public IP mapping.  
4. Accept and log sessions.  
5. In dynamic mode only, generate up to the capped number of synthetic files when categories fire.  
6. On logout, disconnect, idle timeout, or safety trip: tear down, wipe volatile state, and bring up the next clean instance.

Fast recycle means each attacker, as much as possible, faces a fresh, known starting state. Persistent attacker-installed malware is not retained between recycles.

### Security policy

**Entry / intentional vulnerability.** Attackers “breach” by authenticating to SSH using credentials we deliberately expose for research (weak or well-known decoy accounts). SSH is the primary and intended point of entry. We are not relying on unpatched remote code execution beyond that controlled login path for the core study.

**Firewall and network controls.** Inbound access is limited to SSH on the research addresses. Egress from the guest is tightly restricted (deny-by-default outbound where compatible with course and campus networking requirements) so the decoy cannot be used as a reliable launchpad for attacking third parties. Management access to hypervisors and logging hosts is separate from the attacker-facing network path.

### Risk analysis beyond a normal high-interaction decoy

Beyond standard high-interaction risks (attacker attempts to escalate, pivot, or abuse CPU/network), our dynamic condition adds a software component that writes files into the live guest based on attacker input. Risks include:

- generator bugs writing unexpected paths or filling disks  
- logic that accidentally creates confusing or overly enticing content  
- operational complexity from rapid recycle  

Mitigations: template-only generation (no LLM), path allowlists, per-session generation caps, disk quotas, rapid recycle, egress controls, and automated Slack alerts on health and anomaly signals. Synthetic content never includes real secrets.

---

## Data Collection

### Collection process and tools

We collect data continuously from each guest and from the host management layer.

**Planned collection tools (no Snoopy logger):**

- SSH authentication and session metadata from the SSH service and system auth logs  
- Command and interactive session recording through our planned session logging approach on the guest (team-implemented command capture tied to the SSH session, not Snoopy)  
- Filesystem access signals needed to count files accessed and to detect behavior categories (for example, audit-style file watch or application-level hooks around read/open of research paths)  
- A small custom component for behavior detection and template artifact generation in the dynamic condition  
- Centralized log shipping from guests to a collector on the trusted management network  
- Slackbot integration for operational alerts (instance up/down, recycle failures, generation errors, disk/network anomalies)

All timestamps are synchronized so we can align login, commands, generation events, and file access.

### Dataset (direct and indirect measures)

**Direct measures.** Session ID, condition (static/dynamic), assigned IP/instance ID, login time, logout or recycle time, session length, command transcripts or command list, command count, list of files accessed, list of artifacts generated (dynamic only), whether each generated artifact was accessed, and time between generation and first access.

**Indirect / derived measures.** Command diversity, behavior-category hits, whether the session appears automated, breadcrumb depth (how many generated files were touched in sequence), and engagement scaled by files available at end of session.

Data are stored for analysis in structured form (for example, JSON or CSV session summaries plus raw logs). No real user credentials from outside the experiment are collected by design; all bait content is synthetic.

---

## Monitoring

Monitoring is primarily technical rather than human-attended. The host and guest emit health and security signals to a collector; a Slackbot posts to a team channel when attention is needed.

**Automated monitoring covers:**

- instance liveness and recycle success/failure  
- SSH service availability on each public mapping  
- disk, CPU, and unexpected egress attempts  
- artifact generator errors or cap violations  
- sudden volume spikes that may indicate abuse of the decoy  

**Human role.** Team members are not expected to watch live sessions continuously. Instead, designated members review the Slack channel on a daily schedule during the collection window and respond to alerts (failed recycles, host issues, policy violations). Holiday and break coverage is handled by keeping alerting on and assigning an on-call rotation of teammates who check Slack at agreed intervals; if campus networking or power events take systems offline, the next on-call member restores the recycle pipeline when service returns.

We are not using block randomization and not using Snoopy, per interview guidance.

---

## Backup Research Question(s)

Our core design assumes that enough sessions will either (a) execute enough commands for behavior detection to matter, or (b) show measurable differences in session length, command count, or files accessed between conditions. Given that most visitors may be bots with short scripts, that assumption can fail.

**Backup research question:**  
Among SSH sessions that reach a minimum activity threshold (for example, at least *N* commands or at least one access to a non-default research file), how do static and dynamic conditions compare on session length, command count, and files accessed—and, in the dynamic condition, what fraction of sessions ever access a file that was generated during that same session?

This backup still uses the same infrastructure and logs. It simply reframes analysis around sessions where adaptation had a realistic chance to matter, and it adds a descriptive question about whether generated breadcrumbs are ever followed under live internet traffic. If even the filtered subset shows no difference, we can still report a clear negative result about adaptation under bot-dominated SSH probing, which remains a useful contribution.

A second lightweight fallback, if generation almost never triggers, is descriptive: which behavior categories appear in the wild on our decoys, and how often, without claiming an engagement effect. That keeps the final analysis requirement satisfiable even if the causal comparison is underpowered.

---

## Project Planning

*[Omitted for now per team request. Will include schedule rationale, Gantt/calendar visualization, roadblocks, and contingencies in a later revision.]*

---

## Appendix A — Interview Feedback Incorporated (for team use; optional in final paper)

| Interview point | How this proposal responds |
| --- | --- |
| LLM security / university permission / never done before | LLM removed from initial design; template-only generator |
| Too many variables; unclear what is tested | Single independent variable: static vs behavior-responsive file generation; fixed starter filesystem; generation cap |
| Catering to everything / “more than they ask for” | Only add capped synthetic files after category detection; no unrestricted wish fulfillment |
| Consistency hard | Shared synthetic values within a session; fixed template families |
| Why not hard-coded exhaustive scripts? | Behavior categories instead of per-command scripts |
| Pick a side for hypothesis + a metric | Directional: dynamic increases session length, command count, files accessed |
| No block randomization | Random condition assignment per instance bring-up only |
| No Snoopy | Explicitly excluded; other session logging planned |
| Slackbot for monitoring | Included as primary alert path |

---

## Appendix B — Open items to confirm before finalizing

1. Exact maximum generated artifacts per session (draft uses **3**).  
2. Exact idle timeout and recycle triggers compatible with “seconds-scale” recycle.  
3. Exact decoy SSH username/password policy allowed by course staff.  
4. Minimum command threshold *N* for the backup analysis.  
5. Initial filesystem file list (paths and names) for the shared starter image.  
6. Course dates for the Project Planning / Gantt section.  
7. Citations (≥3 academic, ≥1 reputable, including one similar study).  
8. Cover page metadata (title, names, group number, team name, course ID).
