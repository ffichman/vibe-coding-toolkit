# bootstrap/

Adoção do vibe-coding-toolkit nas máquinas e repositórios (fork `ffichman/vibe-coding-toolkit`, tag `baseline-revisado`).

Todos os scripts são **dry-run por padrão**. Nada muda sem `--apply`.
Sem comentários inline e sem colchetes sem escape (compatível com o zsh do THE-NEXTT).

## install-global.sh

Instala no `~/.claude` do usuário, de forma idempotente:

| Item | Como | Por quê |
|---|---|---|
| Superpowers | `claude plugin marketplace add anthropics/claude-plugins-official` + `claude plugin install superpowers@claude-plugins-official` | marketplace oficial |
| Context7 MCP | `claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp` | endpoint HTTP: não executa `npx ctx7` sem versão (achado A6) |
| agent-browser | `npm install -g agent-browser@0.38.2` + `agent-browser install` | versão fixa (achado A7); nunca usa sudo |
| hooks | `~/.claude/hooks/vct/session-context.mjs` + merge no `~/.claude/settings.json` | SessionStart, `timeout: 5`, caminho absoluto, só injeta contexto, nunca bloqueia (achado B2) |

O `settings.json` existente é preservado: merge com backup `settings.json.bak-vct-<data>`; se o JSON for inválido, o script aborta sem tocar no arquivo.
`CONTEXT7_API_KEY` (opcional) é lida do ambiente e nunca é impressa.

```bash
bash bootstrap/install-global.sh
bash bootstrap/install-global.sh --apply
bash bootstrap/install-global.sh --apply --only hooks,context7
```

Via SSH (o script vai por stdin e roda com bash, então o zsh remoto não interpreta nada):

```bash
bash bootstrap/remote.sh the-dock
bash bootstrap/remote.sh the-nextt
bash bootstrap/remote.sh the-nextt --apply
```

`the-dock` = `rodrigofichman@10.100.0.4`, `the-nextt` = `thenextt@10.100.0.2`. Também aceita `usuario@host`.

## apply-repo.sh

```bash
bash bootstrap/apply-repo.sh <caminho-do-repo>
bash bootstrap/apply-repo.sh <caminho-do-repo> --apply
bash bootstrap/apply-repo.sh <caminho-do-repo> --apply --install-deps --measure
```

| Stack detectada | O que é criado |
|---|---|
| JS/TS (`package.json`/`tsconfig*.json`) | `CLAUDE.md`, `.claude/memory/MEMORY.md`, `.quality/` com ESLint só-medição (`MAX_LINES=350`, tudo `warn`) |
| Swift (`Package.swift`, `.xcodeproj`, `.xcworkspace`, `*.swift`) | `CLAUDE.md`, `.claude/memory/MEMORY.md`, `.quality/` com SwiftLint só-medição (`file_length` 350) |
| outros | só `CLAUDE.md` |
| repo na `exclusions.txt` (RFF Grit) | só `CLAUDE.md` com guardrails + medição efêmera (configs em diretório temporário) |

Regras:
- Nunca sobrescreve arquivo existente (avisa se for diferente).
- Nunca refatora, nunca roda `--fix`, nunca faz commit no repo alvo.
- Não altera `eslint.config.*`, `.swiftlint.yml`, `package.json` nem hooks de git existentes.
- `--install-deps` é a única opção que mexe em dependências: adiciona `eslint@9.39.5` (+ `typescript-eslint@8.71.1` em TS) com versão exata, usando o gerenciador do lockfile. Se já houver ESLint local, não faz nada.
- A medição (`bash .quality/measure.sh`) sempre sai com código 0. Sem ESLint ou SwiftLint instalado, cai para contagem de linhas.

## apply-all.sh

Acha todos os repositórios git sob uma ou mais raízes e roda o `apply-repo.sh` em cada um, com resumo em tabela e um log por repo.

```bash
bash bootstrap/apply-all.sh ~/Aethel ~/nextthouse-os --log-dir ~/Aethel/tools/vct-all
bash bootstrap/apply-all.sh ~/Aethel --apply
```

Pula `node_modules`, `worktrees`, `mirrors`, `backups*`, `obsoleto*`, `Library`, `.Trash`, `.build` e `Pods`. Padrão: `--dry-run`. Profundidade padrão: 4 (`--depth N`).
