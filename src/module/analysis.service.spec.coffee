beforeEach module 'analysis'

describe 'analysis service', ->
    analysisService = null

    injected = ($injector) ->
        analysisService = $injector.get('analysisService')

    beforeEach(inject(injected))

    it "test_basic", ->
        data =
            frames: [['00',1,'0'], ['00',1,'1'], ['00',1,'2'], ['00',1,'3'], ['00',1,'4']]
            samples: [
                threads:
                    1: [0, 1, 2]
            ]
        ret = analysisService.profileToFlame(data)
        expected =
            name: "entry"
            value: 1
            children: [
                name: "00+1:2"
                id: 2
                value: 1
                children: [
                    name: "00+1:1"
                    id: 1
                    value: 1
                    children: [
                        name: "00+1:0"
                        id: 0
                        value: 1
                        children: []
                    ]
                ]
            ]
        expect(JSON.stringify(ret)).toEqual(JSON.stringify(expected))
        return

    it "test_fixture", ->
        ret = analysisService.profileToFlame(FIXTURES['profile.fixture.json'])
        expect(ret.value).toEqual(3)
        return

    it "test_basic_cpu", ->
        data =
            samples: [
                time : 1471718745.52914,
                mem: percent: 20
                cpu : [
                    34.4,
                    12.1,
                    39.7,
                    10.9
                 ]
            ,
                time : 1471718746.52914,
                mem: percent: 30
                cpu : [
                    30.4,
                    10.1,
                    30.7,
                    0.9
                 ]
            ]
        expected = [
            key: 'cpu'
            values: [
                x: 0
                y: 24.275000000000002
            ,
                x: 1
                y: 18.025000000000002
            ]
        ,
            key: 'mem'
            values: [
                x: 0
                y: 20
            ,
                x: 1
                y: 30
            ]
        ,
            key: 'load'
            values: [
                x: 1
                y: 100
            ]
        ]
        ret = analysisService.profileToCpu(data)
        expect(JSON.stringify(ret)).toEqual(JSON.stringify(expected))

    it "test_fixture_cpu", ->
        ret = analysisService.profileToCpu(FIXTURES['profile.fixture.json'])
        expect(ret.length).toEqual(3)
        expect(ret[0].key).toEqual('cpu')
        expect(ret[1].key).toEqual('mem')
        expect(ret[2].key).toEqual('load')
        return

    it "test_fixture_details", ->
        ret = analysisService.getFrameStats(FIXTURES['profile.fixture.json'], 15)
        expect(ret.name).toEqual('/twisted/web/http.py+768:requestReceived')
        expect(ret.callers[0].name).toEqual('/twisted/web/http.py+1781:allContentReceived')
        expect(ret.callees[0].name).toEqual('wisted/web/server.py+183:process')
