// Exercise the real DSH middleware with two independent session directories.
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { apply } from '../dsh/index.mjs'

assert.ok(process.env.DOSI_DEV_BIN_DIR, 'DOSI_DEV_BIN_DIR must name the local CLI build')
const root = mkdtempSync(join(tmpdir(), 'dosi-dsh-model-'))
const originalPath = process.env.PATH
try {
  process.env.DOSI_PLUGIN_DATA = join(root, 'plugin-data')
  process.env.DOSI_MODEL_STATE_DIR = join(root, 'cache')
  process.env.DOSI_SECRETS_FILE = join(root, 'absent-secrets')
  for (const key of ['DOSI_MODEL', 'DOSI_ONTOLOGY', 'DOSI_MAPPING', 'DOSI_SECRETS_ENV']) delete process.env[key]
  const historical = `version: 0.2.0.dev0
semantic_model:
  - name: shop
    datasets:
      - name: orders
        source: orders
    metrics: []
`
  const projects = ['read-session', 'write-session'].map(name => {
    const path = join(root, name)
    mkdirSync(join(path, 'dosi'), { recursive: true })
    writeFileSync(join(path, 'dosi/model.yaml'), historical)
    return path
  })
  let execute
  apply({
    skills: { register() {} },
    workingDirectory: { async ensure(agent) { return agent.cwd } },
    on(event, handler) { assert.equal(event, 'tools/execute'); execute = handler },
  })
  let nextCalls = 0
  const read = await execute({ name: 'read', arguments: { path: 'dosi/model.yaml' }, agent: { cwd: projects[0] } }, async () => {
    nextCalls++
    assert.match(readFileSync(join(projects[0], 'dosi/model.yaml'), 'utf8'), /^name: shop$/m)
    return { content: [{ type: 'text', text: 'read' }] }
  })
  assert.equal(read.isError, undefined)
  assert.equal(nextCalls, 1)
  assert.equal(readFileSync(join(projects[1], 'dosi/model.yaml'), 'utf8'), historical)
  const edited = historical.replace('  - name: shop\n', '  - name: shop\n    description: First edit\n')
  const write = await execute({ name: 'write', arguments: { path: 'dosi/model.yaml', content: edited }, agent: { cwd: projects[1] } }, async () => {
    nextCalls++
    assert.match(readFileSync(join(projects[1], 'dosi/model.yaml'), 'utf8'), /^name: shop$/m)
    writeFileSync(join(projects[1], 'dosi/model.yaml'), edited)
    return { content: [{ type: 'text', text: 'written' }] }
  })
  assert.equal(write.isError, undefined)
  assert.deepEqual(write.content, [{ type: 'text', text: 'written' }])
  assert.equal(nextCalls, 2)
  const current = readFileSync(join(projects[1], 'dosi/model.yaml'), 'utf8')
  assert.match(current, /^name: shop$/m)
  assert.match(current, /^description: First edit$/m)
  assert.equal(readFileSync(join(projects[0], 'dosi/model.yaml'), 'utf8').includes('First edit'), false)
  console.log('DSH: first-write continuation, post-edit migration, and per-session paths passed')
} finally {
  process.env.PATH = originalPath
  rmSync(root, { recursive: true, force: true })
}
