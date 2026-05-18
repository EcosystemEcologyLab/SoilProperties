# CLAUDE.md — SoilProperties

## Lab Principles Source

<!-- Record the commit hash of EcosystemEcologyLab/lab-principles that was
     used to initialise this project. This makes the version of standards
     traceable for any published result. -->

- Repository: EcosystemEcologyLab/lab-principles
- Commit:41dd83436ad1bd15520659f0969b64e147ae3e15
- Copied:2026-05-18
- SCIENCE_PRINCIPLES.md v1.0
- SCIENCE_PRINCIPLES_PIPELINES.md v1.0
- SCIENCE_PRINCIPLES_TEXT_ANALYSIS.md NA

---

## Project Context

In natural ecosystems, however, most research has focused on evaluating the 
influence of soil moisture or climate variables on ecosystem productivity, often 
overlooking the role of soil properties themselves. Other studies have attempted
to model these interactions and have found that certain soil properties, such as
soil water retention, exert a strong influence on Gross Primary Productivity 
(GPP), and may be even more important in semi-arid ecosystems.Despite this, the 
influence of specific soil properties on plant function remains poorly 
constrained in arid ecosystems due to the lack of field observations. To address
this gap, we characterize plant responses to changing precipitation 
conditions (i.e., induced drought) across several soil types at the Biosphere 2. 

**PI:** David J.P. Moore, University of Arizona  
**Collaborators:** Angie Abarzua Munoz; Lindsey Bell  
**Funding:** 
**Repository:** https://github.com/EcosystemEcologyLab/SoilProperties  

---

## Hard Rules — Read These First



### 1. Data sources


### 2. Credentials and secrets
All credentials must be read from environment variables. Never hard-code
any credential, API key, password, or token. See `.env.example` for the
full list of required environment variables.

### 3. Data files
The following directories are gitignored and must never be committed:

The following directories are git-tracked:
[LIST TRACKED DIRECTORIES e.g. data/snapshots/, data/overrides/]

### 4. [ADD PROJECT-SPECIFIC HARD RULES AS NEEDED]

---

## Environment Variables

<!-- List all environment variables the project uses. Copy from .env.example. -->

| Variable | Purpose | Default |
|---|---|---|
| [VARIABLE_NAME] | [Purpose] | [Default or "required"] |

---

## Pipeline Execution Order

<!-- If the project has numbered scripts, list them here with a one-line
     description of each. If not applicable, remove this section. -->

```
[01_script.R]   → [What it does]
[02_script.R]   → [What it does]
```

---

## Coding Conventions

### Language and style
- Primary language: [R / Python / other]
- [Add style guide reference e.g. tidyverse style guide URL]
- [Add pipe preference e.g. use base R pipe |> not %>%]

### Package preferences
- [List preferred packages for data manipulation, plotting, etc.]
- Do not introduce new package dependencies without discussion

### Functions
- Every function must have documentation (roxygen2 for R, docstrings for Python)
- Every function must have at least one test

---

## QC and Quality Standards

<!-- Describe the quality control approach for this project. If using
     FLUXNET QC flags, use the template below. Otherwise adapt. -->

[DESCRIBE QC APPROACH AND THRESHOLDS]

---

## Confidence and Quality Vocabulary

<!-- State whether this project uses the shared HIGH/MEDIUM/LOW/UNKNOWN
     vocabulary from SCIENCE_PRINCIPLES.md, or a project-specific system.
     If using a project-specific system, define it here. -->

[ADOPT OR DEFINE CONFIDENCE VOCABULARY]

---

## Output Metadata

<!-- Every output must carry provenance metadata per SCIENCE_PRINCIPLES_PIPELINES.md.
     Describe the format used in this project (companion JSON, CSV header, etc.)
     and where session info is saved. -->

[DESCRIBE OUTPUT METADATA FORMAT]

---

## Exclusion Logging

<!-- Describe where and how exclusions are logged in this project,
     per SCIENCE_PRINCIPLES_PIPELINES.md conventions. -->

[DESCRIBE EXCLUSION LOG LOCATION AND FORMAT]

---

## Known Pending Items

<!-- List any known limitations, stopgap functions, or pending upstream
     fixes that affect this project. Update this list as issues are resolved. -->

| Item | Tracked in |
|---|---|
| [Description] | [GitHub issue URL] |

---

## Data Use and Citation

<!-- List any data use agreements, required citations, or attribution
     requirements that apply to data used in this project. -->

[LIST REQUIRED CITATIONS AND DATA USE OBLIGATIONS]
