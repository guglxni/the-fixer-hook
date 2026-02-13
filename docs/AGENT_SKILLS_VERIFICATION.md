## Agent Skills Verification

Date: 2026-02-01

Summary:
- Performed skill installation and verification for Vercel agent skills and the `find-skills` utility.
- Verified Gemini CLI can discover and use the Vercel skills; Copilot/`npx` skill listing requires a reload to pick up symlinked skills.

Actions performed:
- Cloned `vercel-labs/agent-skills` to `~/.agents/src/vercel-agent-skills` and symlinked each skill into `~/.agents/skills` and `~/.gemini/skills`.
- Ran `gemini skills list` and confirmed the following are present and enabled:
  - `vercel-composition-patterns`
  - `vercel-react-best-practices`
  - `vercel-react-native-skills`
  - `web-design-guidelines`
- Executed a live review with Gemini using `vercel-composition-patterns` against `docs/INTEGRATION_GUIDE.md`. Gemini returned a concise review and three actionable items (extracted and saved in session output).

Commands used (for reproducibility):
```
npx skills add vercel-labs/agent-skills -g
git clone --depth=1 https://github.com/vercel-labs/agent-skills.git ~/.agents/src/vercel-agent-skills
mkdir -p ~/.agents/skills ~/.gemini/skills
for d in ~/.agents/src/vercel-agent-skills/skills/*; do name=$(basename "$d"); ln -sfn "$d" "$HOME/.agents/skills/$name"; ln -sfn "$HOME/.agents/skills/$name" "$HOME/.gemini/skills/$name"; done
gemini skills list
printf "$(sed 's/"/\\"/g' docs/INTEGRATION_GUIDE.md)" | gemini -p "Using the vercel-composition-patterns skill, review the piped file contents (INTEGRATION_GUIDE.md) for React composition concerns, identify 3 concise actionable improvements, and list any patterns to refactor. Keep suggestions brief and reference section headings."
```

Observed outputs (high level):
- `gemini skills list` showed all four `vercel-*` skills as `Enabled` and listed their SKILL.md locations under `~/.gemini/skills`.
- The `gemini` run returned a short review recommending: extract logic into a `useReferralSwap` hook, invert control via props (`onSwap`), and lift `referrer` state to a controlled pattern.
- `npx skills list -g` initially showed only `find-skills`. After symlinking, the Vercel skill folders exist under `~/.agents/skills` (contain `SKILL.md`) but `npx skills list -g` output may still reflect a cached registry.

Conclusions:
- Gemini CLI: working — it can discover and run the Vercel skills and return useful output.
- Copilot/`npx` skills: partially set — skill files are installed/symlinked into `~/.agents/skills`, but the `npx skills` listing may require an agent/extension reload to refresh its registry/cache.

Next steps (to fully confirm Copilot/Opus):
1. Reload the GitHub Copilot/Opus agent process or VS Code extension to force skill discovery.
2. Run `npx skills list -g` and `npx skills list` inside the project to confirm the skills appear.
3. Optionally run a quick Copilot/Opus prompt that triggers one of the `vercel-*` skills (if supported) to validate end-to-end.

File created by automation: `docs/AGENT_SKILLS_VERIFICATION.md`
