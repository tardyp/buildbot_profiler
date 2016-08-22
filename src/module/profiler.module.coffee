# Register new module
angular.module('profiler', ['analysis'])

# Register new state
class State extends Config
    constructor: ($stateProvider, glMenuServiceProvider) ->

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
            templateUrl: "profiler/views/profiler.html"
            name: "profiler"
            url: "/profiler/profiler"
            data:
                group: groupName
                caption: 'Profiler'
                icon: 'area-chart'

class ProfilerPage extends Controller
    self = null
    constructor: ($scope, $state, $http, $interval, analysisService) ->
        self = this
        self.$scope = $scope
        graphLoaded = false
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
                    if progress.loaded = progress.total
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
        flamegraph.onClick (d)-> $scope.$apply ->
            $scope.frameStats = analysisService.getFrameStats($scope.data, d.id)

        $scope.updateFlame =  _.debounce ->
            flamedata = analysisService.profileToFlame($scope.data, $scope.extent)
            d3.select('#profile').html("")
            d3.select('#profile').datum(flamedata).call flamegraph
        , 100

        $scope.loadGraphFromAPI = ->
            d3.json 'profiler/api/profiles', (error, data) ->
                if error
                    return console.warn(error)

                $scope.loadGraph(data)

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
