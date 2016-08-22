### ###############################################################################################
#
#   This module contains all configuration for the build process
#
### ###############################################################################################
ANGULAR_TAG = "~1.5.3"

config =

    ### ###########################################################################################
    #   Name of the plugin
    ### ###########################################################################################
    name: 'profiler'


    ### ###########################################################################################
    #   Directories
    ### ###########################################################################################
    dir:
        # The build folder is where the app resides once it's completely built
        build: 'buildbot_profiler/static'

    ### ###########################################################################################
    #   Bower dependancies configuration
    ### ###########################################################################################
    bower:
        deps:
            "d3":
                version: "~3.5.5"
                files: "d3.js"
            "nvd3":
                version: "~1.8.4"
                files: "build/nv.d3.js"
            "d3-tip":
                version: "~0.6.7"
                files: 'index.js'
            'd3-flame-graph':
                version: '~0.4.3'
                files: 'src/d3.flameGraph.js'
        testdeps:
            jquery:
                version: '2.1.1'
                files: 'dist/jquery.js'
            angular:
                version: ANGULAR_TAG
                files: 'angular.js'
            lodash:
                version: "~3.10.1"
                files: 'lodash.js'
            "angular-mocks":
                version: ANGULAR_TAG
                files: "angular-mocks.js"

    buildtasks: ['scripts', 'styles', 'fonts', 'imgs',
        'index', 'tests', 'generatedfixtures', 'fixtures']

    karma:
        # we put tests first, so that we have angular, and fake app defined
        files: ["tests.js", "scripts.js", 'fixtures.js']
module.exports = config
