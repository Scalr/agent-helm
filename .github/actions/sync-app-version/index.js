const yaml = require('js-yaml')
const core = require('@actions/core')
const exec = require('@actions/exec')
const github = require('@actions/github')
const semver = require('semver')
const fs = require('fs')
const path = require('path')

const chartsDir = path.join(process.env.GITHUB_WORKSPACE, 'charts')
const appVersion = "0.42.0"
// const appVersion = core.getInput('app_version', { required: true })

function getCharts () {
  const files = fs.readdirSync(chartsDir)
  const directories = files.filter((file) => {
    const filePath = path.join(chartsDir, file)
    return fs.statSync(filePath).isDirectory()
  })
  core.debug(`Charts: ${directories}`)
  return directories
}

function updateCharts () {
  const charts = getCharts()
  core.info(`The appVersion ${appVersion}`)
  charts.forEach(function (chart) {
    const chartPath = path.join(chartsDir, chart, 'Chart.yaml')
    const chartData = yaml.load(fs.readFileSync(chartPath, 'utf8'))

    chartData.appVersion = appVersion
    chartData.version = semver.inc(chartData.version, 'patch')
    const updatedYaml = yaml.dump(chartData, {"lineWidth": -1})
    fs.writeFileSync(chartPath, updatedYaml, 'utf8')
    core.info(`The new version of ${chart} is ${chartData.version}`)
  })
}

async function pushChanges () {
  await exec.exec('git config user.name "github-actions[bot]"')
  await exec.exec('git config user.email "github-actions[bot]@users.noreply.github.com"')
  await exec.exec(`git checkout -b ${process.env.PR_BRANCH}`)
  await exec.exec('git add charts')
  await exec.exec(`git commit -m "Sync appVersion: ${appVersion}`)
  await exec.exec(`git push origin ${process.env.PR_BRANCH} --force`)
}

async function draftPR () {
  try {
    const octokit = github.getOctokit(process.env.GH_TOKEN)
    const createResponse = await octokit.rest.pulls.create({
      owner: github.context.repo.owner,
      repo: github.context.repo.repo,
      title: `Sync appVersion ${appVersion} triggered by upstream release workflow`,
      head: process.env.PR_BRANCH,
      base: process.env.GITHUB_REF_NAME
    });
    core.notice(
      `Created PR #${createResponse.data.number} at ${createResponse.data.html_url}`
    );
  } catch (err) {
    core.setFailed(`Failed to create pull request: ${err}`)
  }
}

async function run () {
  try {
    updateCharts()
    // await pushChanges()
    // await draftPR()
  } catch (err) {
    return core.setFailed(`Error: ${err}`)
  }
}

run()
