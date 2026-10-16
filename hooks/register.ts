import type { EngineInterface, Register } from 'claude-code'

// L1 (Claude Code only): a status line with the project's dosi stage, and a
// /dosi command that shows where things stand plus the one next step.
// Presentation only — every fact comes from bin/dosi-progress (RFC §6.8).

const STAGES: Record<string, string> = {
  S0: 'ready',
  S1: 'connected',
  S2: 'model',
  S3: 'lineage',
  S4: 'model',
  S5: 'ontology',
}

async function progress($: EngineInterface, args: string[]): Promise<string> {
  const run = await $.process.run(['sh', `${$.plugin.root}/bin/dosi-progress`, ...args], {
    timeoutMs: 5000,
  })
  return run.exitCode === 0 ? run.stdout.trim() : ''
}

function label(stage: string): string {
  return stage ? `dosi · ${STAGES[stage] ?? stage}` : 'dosi'
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'dosi',
      description: 'Dosi: where this project stands and the next step',
    })
    $.ui.status(label(await progress($, ['stage'])))
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (/(^|[\s/])dosi\s/.test(e.command)) {
      try {
        $.ui.status(label(await progress($, ['stage'])))
      } catch {
        // a status line is never worth failing a tool call over
      }
    }
    return ran
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'dosi' }, async $ => {
    const stage = await progress($, ['stage'])
    const hint = await progress($, ['peek'])
    const first = hint.split('\n')[0].replace(/^(HINT|ASK): /, '')
    return {
      text: `${label(stage || 'S0')} (stage ${stage || 'S0'})\nnext: ${first || 'ask me a data question'}`,
    }
  })
}
