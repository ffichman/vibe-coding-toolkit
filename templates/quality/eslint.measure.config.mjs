// vibe-coding-toolkit — ESLint em MODO SÓ-MEDIÇÃO.
// Tudo é "warn": este config nunca falha build/CI e nunca deve ser usado com --fix.
// Não substitui o eslint.config.* do projeto; é chamado explicitamente por .quality/measure.sh.
// Gerado por bootstrap/apply-repo.sh. MAX_LINES abaixo é o teto de arquivo.
import { createRequire } from "node:module";
import path from "node:path";

import quality from "./eslint-rules/index.cjs";

const MAX_LINES = 350;

const projectRequire = createRequire(path.join(process.cwd(), "package.json"));
let tsParser = null;
try {
  tsParser = projectRequire("typescript-eslint").parser;
} catch {
  try {
    tsParser = projectRequire("@typescript-eslint/parser");
  } catch {
    tsParser = null;
  }
}

const rules = {
  "quality/max-lines": ["warn", { max: MAX_LINES }],
  complexity: ["warn", 12],
  "max-depth": ["warn", 4],
  "max-params": ["warn", 4],
  "max-nested-callbacks": ["warn", 3],
  "max-lines-per-function": [
    "warn",
    { max: 150, skipBlankLines: true, skipComments: true },
  ],
};

const base = {
  plugins: { quality },
  linterOptions: { reportUnusedDisableDirectives: "off" },
  rules,
};

const config = [
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      "**/out/**",
      "**/.next/**",
      "**/.nuxt/**",
      "**/.turbo/**",
      "**/coverage/**",
      "**/vendor/**",
      "**/.quality/**",
      "**/.claude/**",
      "**/*.min.js",
    ],
  },
  {
    ...base,
    files: ["**/*.js", "**/*.mjs", "**/*.cjs", "**/*.jsx"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
  },
];

if (tsParser) {
  config.push({
    ...base,
    files: ["**/*.ts", "**/*.tsx", "**/*.mts", "**/*.cts"],
    languageOptions: {
      parser: tsParser,
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
  });
}

export default config;
