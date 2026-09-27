# Repository Instructions

This repository is a shared, project-agnostic catalog of skills, prompts, and agent instructions intended for global use with tools such as Claude and Copilot. Content tied to one application belongs in that application's repository instead.

## Organization

- Store reusable skills in `skills/<skill-name>/SKILL.md`; keep any required supporting assets beside the skill.
- Store reusable prompts in `prompts/` and reusable instructions in `instructions/`.
- Use tool-neutral content when consumers share the same format. Keep tool-specific variants separate only when formats or behavior genuinely differ.
- Keep resource names stable and descriptive. For skills, the frontmatter `name` must match the containing directory name, and `description` should state when the skill applies.
- Link to existing documentation rather than copying it into a customization file.

## Public Repository

This repository is public. Nothing committed or pushed to the remote may contain sensitive or personal data (GDPR).

- Never commit secrets, tokens, credentials, internal URLs, hostnames, IP addresses, or names of employers, clients, or internal projects.
- Never commit personal data: names, emails, phone numbers, usernames, home directory paths, or any other identifying information about real people.
- Keep machine- or user-specific values in git-ignored files (such as `run.properties`) and commit only sanitized templates with placeholders.
- Before committing, review the staged diff for such content; if in doubt, stop and ask rather than commit.

## External Resources

Skills and collections copied from other repositories are redistributed publicly, so their license must allow it.

- Check the upstream license before adding or updating an external resource. Look at the `LICENSE` file, and also at the README and any licensing notes: a license declared only in a README is missed by GitHub's license detection, and some repositories license subdirectories differently.
- No license found means all rights reserved: do not vendor the resource. Stop and ask, or link to the source instead.
- When the license requires it (MIT, Apache-2.0, BSD...), ship the upstream license text verbatim beside the resource, e.g. `resources/collections/<name>/LICENSE`. Never write a license or copyright line on the author's behalf.
- Credit the source in `README.md` under "Public references": link to the repository, name the license, and describe the resource.

## Authoring and Validation

- Prefer concise, actionable guidance over general explanations. Avoid machine-specific paths and assumptions about a particular project.
- Preserve the resource's expected format and validate frontmatter and internal links when editing it.
- There is no build or test command. Deployment is done by `run.sh` (spec: `run.spec.md`), which symlinks `resources/` into the targets configured in the git-ignored `run.properties`; run `./run.sh help` for commands. Do not assume deployment has happened: check with `./run.sh list`.
- Keep resource authoring independent from deployment destinations. When changing `run.sh`, validate its listing and link behavior against temporary target directories, never by overwriting unrelated user files.