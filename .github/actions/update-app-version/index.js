const yaml = require('js-yaml');
const core = require('@actions/core');
const semver = require('semver');
const fs = require('fs');
const path = require('path');

const chartsDir = path.join(process.env.GITHUB_WORKSPACE, 'charts');

function getCharts() {
    const files = fs.readdirSync(chartsDir);
    const directories = files.filter((file) => {
        const filePath = path.join(chartsDir, file);
        return fs.statSync(filePath).isDirectory();
    });
    core.debug(`Charts: ${directories}`);
    return directories;
}

async function run() {
    try {
        const charts = getCharts()
        const appVersion = core.getInput('app_version', { required: true });
        core.info(`The appVersion ${appVersion}`);
        charts.forEach(function (chart) {
            chartPath = path.join(chartsDir, chart, "Chart.yaml")
            const chartData = yaml.load(fs.readFileSync(chartPath, 'utf8'))

            chartData.appVersion = appVersion;
            chartData.version = semver.inc(chartData.version, 'patch');
            const updatedYaml = yaml.dump(chartData);
            fs.writeFileSync(chartPath, updatedYaml, 'utf8');
            core.info(`The new version of ${chart} is ${chartData.version}`);
        });
    } catch (err) {
        return core.setFailed(`Error: ${err}`)
    }

}

run();
