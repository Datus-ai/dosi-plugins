import { describe, expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { lineageTree } from '../hooks/lineage'
import { extractJson, parseAsk, parseConnections, parseGraph } from '../hooks/parse'

// A project beneath the mod, answered from memory: the files it stats and
// reads, and what bin/dosi and bin/dosi-progress print for each call.

const ROOT = '/work/shop'

const CONNECTIONS = `datasources:
  local:
    type: duckdb
    uri: duckdb:////work/shop/shop.duckdb   # the file
    default: true
  pg:
    type: postgres
    host: pg.internal
    password: \${PG_PASSWORD}
`

const GRAPH = {
  version: 2,
  layers: [{ kind: 'physical_table' }, { kind: 'dataset' }, { kind: 'metric_atomic' }, { kind: 'metric_derived' }],
  nodes: [
    { id: 'table:main.orders', kind: 'physical_table', layer: 0, label: 'main.orders', detail: { table: 'main.orders' } },
    { id: 'table:main.customers', kind: 'physical_table', layer: 0, label: 'main.customers', detail: {} },
    { id: 'dataset:orders', kind: 'dataset', layer: 1, label: 'orders', detail: { source: 'main.orders' } },
    { id: 'dataset:customers', kind: 'dataset', layer: 1, label: 'customers', detail: {} },
    { id: 'metric:revenue', kind: 'metric_atomic', layer: 2, label: 'revenue', detail: { expression: 'SUM(amount)' } },
    { id: 'metric:order_count', kind: 'metric_atomic', layer: 2, label: 'order_count', detail: {} },
    { id: 'metric:aov', kind: 'metric_derived', layer: 3, label: 'aov', detail: { expression: 'revenue / order_count' } },
  ],
  edges: [
    { kind: 'reads_table', source: 'table:main.orders', target: 'dataset:orders' },
    { kind: 'reads_table', source: 'table:main.customers', target: 'dataset:customers' },
    { kind: 'join', source: 'dataset:orders', target: 'dataset:customers' },
    { kind: 'aggregates', source: 'dataset:orders', target: 'metric:revenue' },
    { kind: 'aggregates', source: 'dataset:orders', target: 'metric:order_count' },
    { kind: 'derives', source: 'metric:revenue', target: 'metric:aov' },
    { kind: 'derives', source: 'metric:order_count', target: 'metric:aov' },
  ],
}

const METRICS = [
  { name: 'revenue', kind: 'aggregate', datasets: ['orders'], description: 'completed amount' },
  { name: 'order_count', kind: 'aggregate', datasets: ['orders'], description: '' },
  { name: 'aov', kind: 'derived', datasets: ['orders'], description: 'revenue per order' },
]

const QUERY = {
  dialect: 'duckdb',
  sql: 'SELECT customers.region AS region, SUM(orders.amount) AS revenue FROM main.orders AS orders GROUP BY 1',
  outputs: [{ column: 'revenue', metric: 'revenue' }],
  rows: [
    { region: 'south', revenue: 6951.0 },
    { region: 'east', revenue: 6573.5 },
  ],
}

type World = { stage?: string; peek?: string; issues?: unknown[]; hasModel?: boolean; status: string[]; prompts: string[] }

function project(on: On, world: World) {
  const files: Record<string, number> = {
    [`${ROOT}/dosi-connections.yaml`]: 1,
    ...(world.hasModel === false ? {} : { [`${ROOT}/dosi/model.yaml`]: 2 }),
  }
  on('session.root', () => ({ value: ROOT }))
  on('fs.stat', (_$, e) => {
    const mtimeMs = files[e.path]
    if (!mtimeMs) throw new Error(`ENOENT ${e.path}`)
    return { value: { kind: 'file' as const, size: 1, mtimeMs, isLink: false } }
  })
  on('fs.read', (_$, e) => ({ value: e.path.endsWith('dosi-connections.yaml') ? CONNECTIONS : '' }))
  on('fs.exists', () => ({ value: false }))
  on('fs.list', () => ({ value: [{ name: 'shop.duckdb', kind: 'file' as const, size: 1, mtimeMs: 1, isLink: false }] }))
  on('ui.status', (_$, e) => {
    world.status.push(e.text ?? '')
    return { value: undefined }
  })
  // The engine's own drawing beneath: nothing of the mod's.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine's own</Text>
  })
  on('ui.open', () => ({ value: { isPlaced: true } }) as never)
  on('command.register', () => ({ value: undefined }) as never)
  on('prompt.submit', (_$, e) => {
    world.prompts.push(e.text)
    return { text: e.text } as never
  })
  on('process.run', (_$, e) => {
    const argv = e.argv.join(' ')
    const ok = (out: unknown) => ({
      value: {
        exitCode: 0,
        stdout: typeof out === 'string' ? out : JSON.stringify(out),
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    })
    if (argv.includes('dosi-progress')) {
      if (argv.endsWith(' stage')) return ok(world.stage ?? 'S2')
      if (argv.endsWith(' peek')) return ok(world.peek ?? '')
      return ok('')
    }
    if (argv.endsWith('list datasets')) return ok([{ name: 'orders' }, { name: 'customers' }])
    if (argv.endsWith('list metrics')) return ok(METRICS)
    if (argv.endsWith('list dimensions')) return ok([{ name: 'customers.region' }])
    if (argv.endsWith('validate')) return ok({ issues: world.issues ?? [], compile_errors: [], warnings: [{}] })
    if (argv.endsWith('lineage dump')) return ok(GRAPH)
    return ok({ code: 'unexpected', message: argv })
  })
}

/** `/dosi <args>` as the person types it. */
const dosiCommand = ($: { command: { run: (i: never) => Promise<{ text?: string }> } }, args: string) =>
  $.command.run({ command: 'dosi', args, origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } } as never)

const newWorld = (w: Partial<World> = {}): World => ({ status: [], prompts: [], ...w })

const PANE_PROPS = {
  title: 'dosi',
  isFocused: false,
  bodyColumns: 100,
  placement: 'dock' as const,
  scroll: { offset: 0, bodyRows: 40 },
  view: {},
}

const BAND_PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 6,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 6 },
  view: {},
}

describe('parsers', () => {
  test('connections: names, types and default only, no secrets', async () => {
    const conns = parseConnections(CONNECTIONS)
    expect(conns).toEqual([
      { name: 'local', type: 'duckdb', isDefault: true },
      { name: 'pg', type: 'postgres', isDefault: false },
    ])
    expect(JSON.stringify(conns)).not.toContain('PG_PASSWORD')
    expect(JSON.stringify(conns)).not.toContain('pg.internal')
  })

  test('JSON after stderr warnings and an exit-code line', async () => {
    const text = 'Exit code 1\nwarning: datasource "x" did not parse\n{\n  "code": "unknown_metric",\n  "message": "unknown metric"\n}\n'
    expect(extractJson(text)).toEqual({ code: 'unknown_metric', message: 'unknown metric' })
    expect(extractJson('not json at all')).toBe(undefined)
  })

  test('the ASK line of dosi-progress peek', async () => {
    const peek = 'ASK: Build an ontology now? | Build it now | Later | Never ask again\n(answer with: dosi-progress answer h_ontology yes|later|never)'
    expect(parseAsk(peek)).toEqual({ id: 'h_ontology', text: 'Build an ontology now?', options: ['Build it now', 'Later', 'Never ask again'] })
    expect(parseAsk('HINT: something')).toBe(null)
  })

  test('lineage tree: a derived metric walks back to its tables, joins left out', async () => {
    const g = parseGraph(GRAPH)
    expect(g).not.toBe(null)
    const rows = lineageTree(g!, 'metric:aov').map(r => `${r.prefix}${r.node.label}`)
    expect(rows).toEqual([
      'aov',
      '├─ revenue',
      '│  └─ orders',
      '│     └─ main.orders',
      '└─ order_count',
      '   └─ orders',
    ])
    const down = lineageTree(g!, 'table:main.orders').map(r => r.node.label)
    expect(down).toEqual(['main.orders', 'orders', 'revenue', 'aov', 'order_count', 'aov'])
  })
})

describe('facts', () => {
  test('/dosi reports connection, model and metrics, and the status line follows', async ($, on) => {
    const world = newWorld()
    project(on, world)
    const out = await dosiCommand($ as never, '')
    expect(out.text).toContain('duckdb:local (default) · also pg')
    expect(out.text).toContain('dosi/model.yaml · ✓ valid (1 warning) · 2 datasets · 3 metrics · 1 dimensions')
    expect(out.text).toContain('revenue, order_count, aov')
    expect(out.text).not.toContain('PG_PASSWORD')
    expect(world.status.at(-1)).toBe('dosi · duckdb:local · 2 ds · 3 metrics')
  })

  test('/dosi metrics is a table', async ($, on) => {
    project(on, newWorld())
    const out = await dosiCommand($ as never, 'metrics')
    expect(out.text).toContain('| metric | kind | description |')
    expect(out.text).toContain('| aov | derived | revenue per order |')
  })
})

describe('pane', () => {
  for (const surface of ['terminal', 'desktop'] as const) {
    test(`lineage tree on ${surface}, svg where the surface has it`, async ($, on) => {
      project(on, newWorld())
      await dosiCommand($ as never, 'lineage aov')
      const ui = await $.ui.mount({ plugin: 'dosi', surface, component: 'Pane', requestId: 'dosi-lineage', props: PANE_PROPS })
      expect(await ui.find({ type: 'Text', text: /order_count/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /main\.orders/ })).toBeDefined()
      const svg = await ui.find({ type: 'Svg' })
      if (surface === 'desktop') expect(svg).toBeDefined()
      else expect(svg).toBe(undefined)
      await ui.press({ key: 'tab-metrics' })
      expect(await ui.find({ type: 'Markdown', text: /revenue per order/ })).toBeDefined()
      await ui.unmount()
    })
  }
})

describe('band', () => {
  test('silent when there is nothing to act on', async ($, on) => {
    project(on, newWorld())
    await dosiCommand($ as never, '')
    const ui = await $.ui.mount({ plugin: 'dosi', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
    expect(await ui.find({ type: 'Button' })).toBe(undefined)
    expect(await ui.find({ type: 'Text', text: "engine's own" })).toBeDefined()
    await ui.unmount()
  })

  test('model issues show with a button to the pane', async ($, on) => {
    project(on, newWorld({ issues: [{ severity: 'error', code: 'unknown_column', location: 'x', message: 'column cust_idx is not declared' }] }))
    await dosiCommand($ as never, '')
    const ui = await $.ui.mount({ plugin: 'dosi', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
    expect(await ui.find({ type: 'Text', text: /1 issue · column cust_idx/ })).toBeDefined()
    expect(await ui.find({ key: 'issues' })).toBeDefined()
    await ui.unmount()
  })

  test('an ASK from the progress engine gets buttons', async ($, on) => {
    const world = newWorld({
      peek: 'ASK: Build an ontology now? | Build it now | Later | Never ask again\n(answer with: dosi-progress answer h_ontology yes|later|never)',
    })
    project(on, world)
    await dosiCommand($ as never, '')
    const ui = await $.ui.mount({ plugin: 'dosi', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
    expect((await ui.findAll({ type: 'Button' })).map(b => b.props.label)).toEqual(['Build it now', 'Later', 'Never ask again'])
    await ui.press({ key: 'ask-0' })
    expect(world.prompts.at(-1)).toContain('Build it now')
    await ui.unmount()
  })
})

describe('result rows', () => {
  test('a dosi query result is a table with a footer and SQL on demand', async ($, on) => {
    project(on, newWorld())
    let id = ''
    on('tool.call', (_$, e) => {
      id = e.tool_use_id ?? ''
      return { result: { stdout: JSON.stringify(QUERY), stderr: '', interrupted: false } } as never
    })
    await $.tool.call({ tool: 'Bash', command: 'dosi --format json query --metrics revenue --group-by customers.region --execute' })
    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({
        plugin: 'dosi',
        surface,
        component: 'ToolResult',
        requestId: id,
        props: { tool_use_id: id, tool: 'Bash', isErrored: false, output: { stdout: JSON.stringify(QUERY), stderr: '', interrupted: false } },
      })
      expect(await ui.find({ type: 'Markdown', text: /\| region \| revenue \|/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /duckdb:local · 2 rows/ })).toBeDefined()
      expect(await ui.find({ type: 'Code' })).toBe(undefined)
      await ui.press({ key: 'sql' })
      expect(await ui.find({ type: 'Code' })).toBeDefined()
      await ui.press({ key: 'sql' })
      await ui.unmount()
    }
  })

  test('an errored dosi call reads as what happened and what next', async ($, on) => {
    project(on, newWorld())
    let id = ''
    on('tool.call', (_$, e) => {
      id = e.tool_use_id ?? ''
      return { result: { stdout: 'x', stderr: '', interrupted: false } } as never
    })
    await $.tool.call({ tool: 'Bash', command: 'dosi --format json query --metrics nope --execute' })
    const ui = await $.ui.mount({
      plugin: 'dosi',
      surface: 'terminal',
      component: 'ToolResult',
      requestId: id,
      props: {
        tool_use_id: id,
        tool: 'Bash',
        isErrored: true,
        output: 'Exit code 1\n{"code":"unknown_metric","message":"unknown metric \\"nope\\"","candidates":["revenue","aov"]}',
      },
    })
    expect(await ui.find({ type: 'Text', text: /✗ unknown_metric/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /did you mean: revenue, aov/ })).toBeDefined()
    await ui.unmount()
  })

  test('other Bash rows are left to the engine', async ($, on) => {
    project(on, newWorld())
    let id = ''
    on('tool.call', (_$, e) => {
      id = e.tool_use_id ?? ''
      return { result: { stdout: '[]', stderr: '', interrupted: false } } as never
    })
    await $.tool.call({ tool: 'Bash', command: 'ls -la' })
    const ui = await $.ui.mount({
      plugin: 'dosi',
      surface: 'terminal',
      component: 'ToolResult',
      requestId: id,
      props: { tool_use_id: id, tool: 'Bash', isErrored: false, output: { stdout: '{"rows":[]}', stderr: '', interrupted: false } },
    })
    expect(await ui.find({ type: 'Markdown' })).toBe(undefined)
    expect(await ui.find({ type: 'Text', text: "engine's own" })).toBeDefined()
    await ui.unmount()
  })
})
