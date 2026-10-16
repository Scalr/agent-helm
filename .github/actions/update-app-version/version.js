const semver = require('semver')

function nextChartVersion (currentVersion, latestReleased, changelog) {
  const base = latestReleased && semver.gt(latestReleased, currentVersion)
    ? latestReleased
    : currentVersion
  const unreleased = changelog.split('## [UNRELEASED]')[1]?.split('\n## ')[0] || ''
  const breaking = /^\s*-\s+\*\*BREAKING:\*\*/m.test(unreleased)
  return semver.inc(base, breaking ? 'minor' : 'patch')
}

module.exports = { nextChartVersion }
