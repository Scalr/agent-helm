const yaml = require('js-yaml')
const core = require('@actions/core')
const exec = require('@actions/exec')
const github = require('@actions/github')
const semver = require('semver')
const fs = require('fs')
const path = require('path')

const chartsDir = path.join(process.env.GITHUB_WORKSPACE, 'charts')
const appVersion = core.getInput('app_version', { required: true })
core.info(`The appVersion ${appVersion}`)

function getCharts () {
  const files = fs.readdirSync(chartsDir)
  const directories = files.filter((file) => {
    const filePath = path.join(chartsDir, file)
    return fs.statSync(filePath).isDirectory()
  })
  core.debug(`Charts: ${directories}`)
  return directories
}

function updateCharts (chart) {
  const chartPath = path.join(chartsDir, chart, 'Chart.yaml')
  const chartData = yaml.load(fs.readFileSync(chartPath, 'utf8'))

  chartData.appVersion = appVersion
  chartData.version = semver.inc(chartData.version, 'patch')
  const updatedYaml = yaml.dump(chartData, { lineWidth: -1 })
  fs.writeFileSync(chartPath, updatedYaml, 'utf8')
  core.info(`The new version of ${chart} is ${chartData.version}`)
  return chartData.version
}

function updateCHANGELOG (chart, chartNewVersion) {
  const changelogPath = path.join(chartsDir, chart, 'CHANGELOG.md')
  const newSection = `
## [v${chartNewVersion}]

### Updated

- Bumping chart version to v${chartNewVersion} for scalr-agent v${appVersion}
`
  const updatedChangelog = fs.readFileSync(changelogPath, 'utf8').replace(
    '## [UNRELEASED]\n', `## [UNRELEASED]\n${newSection}`
  )
  fs.writeFileSync(changelogPath, updatedChangelog, 'utf8')
}

async function pushChanges () {
  await exec.exec('git config user.name "github-actions[bot]"')
  await exec.exec('git config user.email "github-actions[bot]@users.noreply.github.com"')
  await exec.exec(`git checkout -b ${process.env.PR_BRANCH}`)
  await exec.exec('touch test')
  await exec.exec('git add test')
  //await exec.exec('git add charts')
  //await exec.exec(`git commit -m "Sync appVersion: ${appVersion}"`)
  await exec.exec(`git commit -m "test"`)
  await exec.exec(`git push origin ${process.env.PR_BRANCH} --force`)
}

async function draftPR () {
  let prNumber
  try {
    const octokit = github.getOctokit(process.env.GH_TOKEN)
    const createResponse = await octokit.rest.pulls.create({
      owner: github.context.repo.owner,
      repo: github.context.repo.repo,
      title: `Sync appVersion ${appVersion} triggered by upstream release workflow`,
      head: process.env.PR_BRANCH,
      base: "master"//process.env.GITHUB_REF_NAME
    })
    prNumber = createResponse.data.number
    core.notice(
      `Created PR #${prNumber} at ${createResponse.data.html_url}`
    ) 
  } catch (err) {
    core.setFailed(`Failed to create pull request: ${err}`)
  }
  return prNumber
}

async function mergePR (prNumber) {
  try {
    const octokit = github.getOctokit(process.env.GH_TOKEN)
    const mergeResponse = await octokit.rest.pulls.merge({
      owner: github.context.repo.owner,
      repo: github.context.repo.repo,
      pull_number: prNumber,
      merge_method: 'squash'
    })
    core.notice(
      `Merged PR #${prNumber}`
    )
  } catch (err) {
    core.setFailed(`Failed to merge pull request: ${err}`)
  }
}

async function helmDocs () {
  await exec.exec('helm-docs')
}

async function run () {
  try {
    // const charts = getCharts()
    // charts.forEach(function (chart) {
    //   const chartNewVersion = updateCharts(chart)
    //   updateCHANGELOG(chart, chartNewVersion)
    // })
    // await helmDocs()
    await pushChanges()
    prNumber = await draftPR()
    await mergePR(prNumber)
  } catch (err) {
    return core.setFailed(`Error: ${err}`)
  }
}

run()