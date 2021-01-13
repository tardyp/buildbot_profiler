'use strict';

const common = require('buildbot-build-common');
const env = require('yargs').argv.env;
const pkg = require('./package.json');

var event = process.env.npm_lifecycle_event;

var isTest = event === 'test' || event === 'test-watch';
var isProd = env === 'prod';

module.exports = function() {
    return common.createTemplateWebpackConfig({
        entry: {
            scripts: './src/module/main.module.js',
            styles: './src/styles/styles.less',
        },
        libraryName: pkg.name,
        pluginName: pkg.plugin_name,
        dirname: __dirname,
        isTest: isTest,
        isProd: isProd,
        extractStyles: true,
        outputPath: __dirname + '/buildbot_profiler/static',
        provideJquery: true,
    });
}();
