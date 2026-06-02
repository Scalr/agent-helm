/******/ (() => { // webpackBootstrap
/******/ 	var __webpack_modules__ = ({

/***/ 638:
/***/ ((module) => {

module.exports = eval("require")("@actions/core");


/***/ }),

/***/ 952:
/***/ ((module) => {

module.exports = eval("require")("@actions/exec");


/***/ }),

/***/ 68:
/***/ ((module) => {

module.exports = eval("require")("js-yaml");


/***/ }),

/***/ 761:
/***/ ((module) => {

module.exports = eval("require")("semver");


/***/ }),

/***/ 896:
/***/ ((module) => {

"use strict";
module.exports = require("fs");

/***/ }),

/***/ 928:
/***/ ((module) => {

"use strict";
module.exports = require("path");

/***/ })

/******/ 	});
/************************************************************************/
/******/ 	// The module cache
/******/ 	var __webpack_module_cache__ = {};
/******/ 	
/******/ 	// The require function
/******/ 	function __nccwpck_require__(moduleId) {
/******/ 		// Check if module is in cache
/******/ 		var cachedModule = __webpack_module_cache__[moduleId];
/******/ 		if (cachedModule !== undefined) {
/******/ 			return cachedModule.exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = __webpack_module_cache__[moduleId] = {
/******/ 			// no module.id needed
/******/ 			// no module.loaded needed
/******/ 			exports: {}
/******/ 		};
/******/ 	
/******/ 		// Execute the module function
/******/ 		var threw = true;
/******/ 		try {
/******/ 			__webpack_modules__[moduleId](module, module.exports, __nccwpck_require__);
/******/ 			threw = false;
/******/ 		} finally {
/******/ 			if(threw) delete __webpack_module_cache__[moduleId];
/******/ 		}
/******/ 	
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/ 	
/************************************************************************/
/******/ 	/* webpack/runtime/compat */
/******/ 	
/******/ 	if (typeof __nccwpck_require__ !== 'undefined') __nccwpck_require__.ab = __dirname + "/";
/******/ 	
/************************************************************************/
var __webpack_exports__ = {};
const yaml = __nccwpck_require__(68)
const core = __nccwpck_require__(638)
const exec = __nccwpck_require__(952)
const semver = __nccwpck_require__(761)
const fs = __nccwpck_require__(896)
const path = __nccwpck_require__(928)

const chartsDir = path.join(process.env.GITHUB_WORKSPACE, 'charts')
const appVersion = core.getInput('app_version', { required: true })
core.info(`The appVersion ${appVersion}`)

function getCharts() {
  const files = fs.readdirSync(chartsDir)
  const directories = files.filter((file) => {
    const filePath = path.join(chartsDir, file)
    return fs.statSync(filePath).isDirectory()
  })
  core.debug(`Charts: ${directories}`)
  return directories
}

function updateCharts(chart) {
  const chartPath = path.join(chartsDir, chart, 'Chart.yaml')
  const chartData = yaml.load(fs.readFileSync(chartPath, 'utf8'))

  chartData.appVersion = appVersion
  chartData.version = semver.inc(chartData.version, 'patch')
  const updatedYaml = yaml.dump(chartData, { lineWidth: -1 })
  fs.writeFileSync(chartPath, updatedYaml, 'utf8')
  core.info(`The new version of ${chart} is ${chartData.version}`)
  return chartData.version
}

function updateCHANGELOG(chart, chartNewVersion) {
  const changelogPath = path.join(chartsDir, chart, 'CHANGELOG.md')
  const newSection = `
## [v${chartNewVersion}]

### Updated

- Bumping chart version to v${chartNewVersion} for scalr-agent v${appVersion}
`
  const updatedChangelog = fs
    .readFileSync(changelogPath, 'utf8')
    .replace('## [UNRELEASED]\n', `## [UNRELEASED]\n${newSection}`)
  fs.writeFileSync(changelogPath, updatedChangelog, 'utf8')
}

async function pushChanges() {
  await helmDocs()
  await exec.exec('git config user.name "github-actions[bot]"')
  await exec.exec('git config user.email "github-actions[bot]@users.noreply.github.com"')
  await exec.exec('git add charts')
  await exec.exec(`git commit -m "Sync appVersion: ${appVersion}`)
  await exec.exec('git push -u origin HEAD')
}

async function helmDocs() {
  await exec.exec('helm-docs')
}

async function run() {
  try {
    const charts = getCharts()
    charts.forEach(function (chart) {
      const chartNewVersion = updateCharts(chart)
      updateCHANGELOG(chart, chartNewVersion)
    })
    await pushChanges()
  } catch (err) {
    return core.setFailed(`Error: ${err}`)
  }
}

run()

module.exports = __webpack_exports__;
/******/ })()
;