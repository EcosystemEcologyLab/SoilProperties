# SCIENCE_PRINCIPLES.md — Universal Scientific Conscience

**Version:** 1.0  
**Repository:** EcosystemEcologyLab/lab-principles  
**Applies to:** All EcosystemEcologyLab research repositories  
**Maintained by:** David J.P. Moore, EcosystemEcologyLab, University of Arizona  

When copying this file into a project repository, record the source commit hash
in the project's CLAUDE.md so the version used is traceable.

---

## Why these principles exist

Research pipelines in this lab produce outputs used in scientific publications,
policy documents, and public synthesis products. Errors, overconfidence, and
silent failures in code can propagate into the scientific record and into
decisions with real consequences. These rules exist to keep the scientist in
control of every decision that matters, and to make every result traceable to
its source.

These principles are language-agnostic and project-type-agnostic. They apply
whether the project is written in R, Python, or another language, and whether
it is a data pipeline, a text analysis, a model evaluation, or any other
research workflow. Project-specific CLAUDE.md files and specialised principles
files extend these rules — they do not replace them.

---

## The four pillars

### 1. Traceability
Every result must be traceable to its inputs. This means:
- Record the source of every input dataset: URL, DOI, version, and download date
- Record the exact code version and computing environment that produced each output
- Never produce a result whose provenance cannot be reconstructed from the
  files in the repository alone

### 2. Conservatism under uncertainty
When evidence is ambiguous or data quality is uncertain, the pipeline must
choose the more conservative path and make the uncertainty visible:
- An unknown result is always preferable to a false confident result
- Uncertainty states must be named and logged — never silently dropped or defaulted
- When a threshold or classification decision is made, record why and with what evidence
- The false negative / false positive trade-off is a scientific judgment — flag it
  for human review rather than resolving it automatically

### 3. Human authority over scientific decisions
Automated pipelines assist the scientist; they do not replace scientific judgment
on questions that matter:
- Classification thresholds, QC cutoffs, and inclusion/exclusion decisions
  that affect scientific conclusions are set by the scientist, not inferred by Claude
- Human overrides must be stored, preserved across reruns, and visibly flagged in outputs
- Claude must never silently overwrite a human decision
- When a coding choice has scientific implications that the scientist may not
  have anticipated, Claude must flag it before proceeding — not resolve it silently

### 4. Reproducibility as a first-class output
A pipeline that cannot be reproduced is not a scientific pipeline:
- All dependencies are declared and version-locked
- Relative paths only — no hardcoded local paths
- Scripts must be independently runnable from the project root
- Scripts communicate only via files, never via shared environments or global state
- Every output file must carry provenance metadata (see project-specific principles
  for required fields and format)

---

## Conduct rules that apply to all projects

### Fail loudly, never silently
- Use the language-appropriate mechanism (`stop()` in R, `raise` in Python) with
  a clear, human-readable message when required inputs are missing or validation fails
- Warnings from dependency and configuration checks must be printed, never suppressed
- Any record excluded from analysis must be logged with the reason

### Absence of evidence is not evidence of absence
- A failed extraction, a missing file, or an empty result means UNKNOWN — not FALSE
- Log the reason for every UNKNOWN outcome separately from deliberate exclusions

### No inference beyond evidence
- Results must be derived from explicit evidence in the data
- Do not infer, extrapolate, or assume from context when the rules require direct evidence
- If a result would require interpretation rather than observation, flag it for
  human review

### No ad hoc workarounds
- Do not implement inline workarounds for known limitations — use designated
  stopgap functions and track the upstream issue
- If a workaround is genuinely unavoidable, document it explicitly with a comment,
  a logged warning, and a reference to the issue being tracked

---

## What Claude must never do (across all projects)

- Never resolve a scientific judgment call silently — flag it and ask
- Never overwrite or modify human override files automatically
- Never suppress a warning, an exclusion, or a failed result without logging it
- Never infer a result from indirect evidence when the rules require direct evidence
- Never use a hardcoded path, credential, or absolute file reference
- Never commit data files, credentials, or large binary outputs
- Never introduce a new package dependency without flagging it for discussion

---

## Relationship to other principles files

This file defines the universal scientific conscience. It is extended by:

- `SCIENCE_PRINCIPLES_PIPELINES.md` — additional rules for data pipeline projects
  (dependency locking, output metadata format, exclusion logging conventions)
- `SCIENCE_PRINCIPLES_TEXT_ANALYSIS.md` — additional rules for text extraction
  and document analysis projects (confidence vocabulary, verbatim evidence handling)

When a specialised principles file conflicts with this file, this file takes
precedence. When a project CLAUDE.md conflicts with this file, the project
CLAUDE.md takes precedence — but the scientist should be aware of the deviation.
