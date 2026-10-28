// DeepSeek Harness entry. DSH loads no Claude Code plugin files, so this
// module wires the same plugin through DSH's own seams:
//   * the skills, registered from skills/*/SKILL.md (ctx.skills);
//   * the plugin's commands on PATH, and a data dir for the dosi it installs;
//   * the two hooks that matter outside Claude Code, run on DSH's tool calls
//     (tools/execute): the config-read guard before a call, and validation
//     after a write to dosi/*.yaml.
// No MCP server: DSH starts one per process with one fixed cwd, while
// dosi-server serves one project's model. The skills fall back to the CLI,
// which runs in each session's own workspace.
import { spawnSync } from 'node:child_process'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

export const name = 'dosi'
export const inject = ['tools', 'skills', 'workingDirectory']

// The hooks match Claude Code's tool names and argument keys.
const CLAUDE_TOOLS = {
  bash: 'Bash', read: 'Read', write: 'Write', edit: 'Edit',
  str_replace_editor: 'Edit', grep: 'Grep', glob: 'Glob',
}
const WRITES = new Set(['Bash', 'Write', 'Edit'])

/** `name` and `description` from a SKILL.md's frontmatter, and its body. */
export function parseSkill(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text)
  if (!m) return null
  const meta = {}
  for (const line of m[1].split(/\r?\n/)) {
    const kv = /^([a-z][a-z-]*):\s*(\S.*)$/.exec(line)
    if (kv) meta[kv[1]] = kv[2].trim()
  }
  if (!meta.name || !meta.description) return null
  return { name: meta.name, description: meta.description, content: text.slice(m[0].length) }
}

/** Run one of the plugin's Claude Code hooks: its message when it exits 2. */
function runHook(script, payload, cwd) {
  const r = spawnSync('sh', [join(root, 'hooks', script)], {
    cwd,
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwd },
    timeout: 120_000,
  })
  return r.status === 2 ? (r.stderr || r.stdout || '').trim() : null
}

function blocked(message) {
  return {
    content: [{ type: 'text', text: message }],
    isError: true,
    error: { message, info: { name: 'DosiGuard', code: 'DOSI_GUARD' } },
  }
}

export function apply(ctx) {
  // Commands the skills call by name (dosi, dosi-reconcile, ...), and where
  // the dosi shim keeps the binary it installs on first use.
  process.env.PATH = `${join(root, 'bin')}:${process.env.PATH ?? ''}`
  process.env.DOSI_PLUGIN_DATA ??= join(homedir(), '.dsh', 'plugin-data', 'dosi')

  const skills = join(root, 'skills')
  for (const entry of readdirSync(skills)) {
    const path = join(skills, entry, 'SKILL.md')
    if (!existsSync(path)) continue
    const skill = parseSkill(readFileSync(path, 'utf8'))
    if (!skill) continue
    ctx.skills.register({
      ...skill,
      path,
      source: 'custom',
      resourceBase: { kind: 'directory', path: join(skills, entry) },
    })
  }

  ctx.on('tools/execute', async (exec, next) => {
    const tool = CLAUDE_TOOLS[exec.name]
    if (!tool) return next()
    const args = exec.arguments ?? {}
    const cwd = exec.agent ? await ctx.workingDirectory.ensure(exec.agent) : process.cwd()
    const input = args.file_path === undefined && typeof args.path === 'string' && tool !== 'Grep' && tool !== 'Glob'
      ? { ...args, file_path: args.path }
      : args
    const payload = { tool_name: tool, tool_input: input, cwd }
    const denied = runHook('guard-config-read.sh', payload, cwd)
    if (denied) return blocked(denied)
    const result = await next()
    if (!WRITES.has(tool) || result?.isError) return result
    const problems = runHook('validate-on-edit.sh', payload, cwd)
    if (!problems) return result
    return { ...result, content: [...(result.content ?? []), { type: 'text', text: problems }] }
  })
}
