# Register new module
angular.module('profiler', ['analysis', 'ui.router', "guanlecoja.ui"])

require("../lib/d3.js")
require("../lib/d3.flameGraph.js")
require("../lib/d3.tip.js")

require("../lib/nv.d3.js")

# Register new state
if window.standalone
    angular.module('profiler').config ["$urlRouterProvider", "$stateProvider", ($urlRouterProvider, $stateProvider) ->
        # Register new state
        $stateProvider.state
            controller: "profilerPageController"
            template: require('./profiler.tpl.jade'),
            name: "profiler"
            url: "/"
        $urlRouterProvider.otherwise('/')
    ]
else
    angular.module('profiler').config ["$stateProvider", "glMenuServiceProvider", ($stateProvider, glMenuServiceProvider) ->
        groupName = 'debug'

        # debug
        glMenuServiceProvider.addGroup
            name: groupName
            caption: 'Debug'
            icon: 'bug'
            order: 0

        # Register new state
        $stateProvider.state
            controller: "profilerPageController"
            template: require('./profiler.tpl.jade'),
            name: "profiler"
            url: "/profiler/profiler"
            data:
                group: groupName
                caption: 'Profiler'
                icon: 'area-chart'
    ]
class ProfilerPage
    self = null
    constructor: ($scope, $state, $http, $interval, analysisService) ->
        self = this
        self.$scope = $scope
        graphLoaded = false
        $scope.standalone = window.standalone
        $scope.start_stop = ->
            $scope.started = !$scope.started
            if $scope.started
                p = $http.get "profiler/api/start", params:
                    frequency: $scope.frequency
                    gatherperiod: $scope.gatherperiod
            else
                p = $http.get("profiler/api/stop")
            p.then ->
                $scope.updateStatus()
        $scope.load = (f)->
            if f.files.length == 1
                r = new FileReader()
                r.onload =  (progress) ->
                    if progress.loaded == progress.total
                        data = JSON.parse(r.result)
                        $scope.loadGraph(data)
                r.readAsBinaryString(f.files[0])

        $scope.updateStatus = ->
            $http.get("profiler/api/status").then (res) ->
                $scope.profile_available = res.data.profile_available
                $scope.started = res.data.started
                $scope.num_samples = res.data.num_samples
                $scope.remaining = res.data.remaining
                if not $scope.frequency
                    $scope.frequency = res.data.frequency
                if not $scope.gatherperiod
                    $scope.gatherperiod = res.data.gatherperiod
                if not graphLoaded and $scope.profile_available
                    $scope.loadGraphFromAPI()
                    graphLoaded=true

        $scope.updateStatus()
        timer = $interval($scope.updateStatus, 5000)
        $scope.$on('$destroy', -> $interval.cancel(timer))
        flamegraph = d3.flameGraph().width(960).height(540)
        console.log(flamegraph.onClick)
        flamegraph.onClick (d)-> $scope.$apply ->
            $scope.frameStats = analysisService.getFrameStats($scope.data, d.id)

        $scope.updateFlame =  _.debounce ->
            flamedata = analysisService.profileToFlame($scope.data, $scope.extent)
            d3.select('#profile').html("")
            d3.select('#profile').datum(flamedata).call flamegraph
        , 100

        $scope.loadGraphFromAPI = ->
            $http.get("profiler/api/profiles").then (res) ->
                $scope.loadGraph(res.data)

        $scope.loadGraph = (data)->
            $scope.data = data
            linedata = analysisService.profileToCpu(data)
            nv.addGraph ->
                chart = nv.models.lineWithFocusChart()
                chart.xAxis.tickFormat d3.format(',.1f')
                chart.yAxis.tickFormat d3.format(',.2f')
                chart.y2Axis.tickFormat d3.format(',.2f')
                d3.select('#cpuviewer svg').datum(linedata).transition().duration(500).call chart
                nv.utils.windowResize chart.update
                chart.focus.dispatch.on "onBrush.updateFlame", (extent) ->
                    $scope.extent = extent
                    $scope.updateFlame()
                    return extent
                $scope.updateFlame()
                return chart

            return

angular.module('profiler').controller('profilerPageController', ["$scope", "$state", "$http", "$interval", "analysisService", ProfilerPage]);