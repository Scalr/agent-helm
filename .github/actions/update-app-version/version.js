const semver = require('semver')

function nextChartVersion (currentVersion, latestReleased, changelog) {
  const base = latestReleased && semver.gt(latestReleased, currentVersion)
    ? latestReleased
    : currentVersion
  const unreleased = changelog.split('## [UNRELEASED]')[1]?.split('\n## ')[0] || ''
  const breaking = /^\s*-\s+\*\*BREAKING:\*\*/m.test(unreleased)
  const increment = breaking ? (semver.major(base) === 0 ? 'minor' : 'major') : 'patch'
  return semver.inc(base, increment)
}

module.exports = { nextChartVersion }
