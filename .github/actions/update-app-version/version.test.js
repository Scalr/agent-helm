const assert = require('node:assert/strict')
const { test } = require('node:test')
const { nextChartVersion } = require('./version')

const breaking = '## [UNRELEASED]\n\n### Changed\n\n- **BREAKING:** Reject duplicate environment variables.\n'

test('bumps the minor version for breaking changes before 1.0', () => {
  assert.equal(nextChartVersion('0.6.8', '0.6.8', breaking), '0.7.0')
})

test('keeps the major version for breaking changes from 1.0 onward', () => {
  assert.equal(nextChartVersion('1.6.8', '1.6.8', breaking), '1.7.0')
})

test('uses patch bumps after the breaking entry has been released', () => {
  const changelog = breaking.replace('## [UNRELEASED]', '## [UNRELEASED]\n\n## [v0.7.0]')
  assert.equal(nextChartVersion('0.7.0', '0.7.0', changelog), '0.7.1')
})

test('starts from the newest released version', () => {
  assert.equal(nextChartVersion('0.6.8', '0.7.2', breaking), '0.8.0')
})

test('preserves a chart version newer than the latest release', () => {
  assert.equal(nextChartVersion('0.8.1', '0.7.0', '## [UNRELEASED]\n'), '0.8.2')
})

test('uses a patch bump for a chart without a released version or breaking entry', () => {
  assert.equal(nextChartVersion('0.1.0', null, '## [UNRELEASED]\n'), '0.1.1')
})
