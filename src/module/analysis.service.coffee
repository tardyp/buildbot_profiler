angular.module('analysis', [])
class Analysis extends Service("analysis")
    constructor: () ->
        children_to_array = (v) ->
            v.children = _.values(v.children)
            v.children.forEach(children_to_array)
        makeName = (info) ->
            try
                return "#{info[0]}+#{info[1]}:#{info[2]}"
            catch error
                console.log "undefined frame", info
                return "<undefined>"
        simplifyFlame = (flame, threshold) ->
            flame.children = flame.children.filter (v) -> v.value >= threshold
            flame.children.forEach (v) -> simplifyFlame(v, threshold)
            # fold flames that have one child
            while flame.children.length == 1
                child = flame.children[0]
                flame.children = child.children
                flame.name = flame.name + '←' + child.name
        return {
        profileToFlame: ({frames, samples}, extent) ->
            ret = _.cloneDeep
                name: 'entry'
                value: 0
                children: {}
            start = samples[0].time
            for sample in samples
                ts = sample.time - start
                if extent? and (ts < extent[0] or ts > extent[1])
                    continue
                for tid, curframes of sample.threads
                    ret.value += 1
                    cur = ret.children
                    for i in [curframes.length-1..0]
                        frameid = curframes[i]
                        if not cur.hasOwnProperty(frameid)
                            info = frames[frameid]
                            cur[frameid] = {
                                name: makeName(info)
                                id: frameid
                                value:0
                                children: {}
                            }
                        cur[frameid].value += 1
                        cur = cur[frameid].children
            children_to_array(ret)
            simplifyFlame(ret, ret.value/7000)
            return ret

        getFrameStats: ({frames, samples}, frameid, extent) ->
            ret = {}
            ret.name = makeName(frames[frameid])
            ret.callers = {}
            ret.callees = {}
            ret.totsamples = 0

            increaseStats = (d, i) ->
                if not d.hasOwnProperty(i)
                    d[i] =
                        name: makeName(frames[i])
                        samples: 0
                d[i].samples += 1

            start = samples[0].time
            for sample in samples
                ts = sample.time - start
                if extent? and (ts < extent[0] or ts > extent[1])
                    continue
                for tid, curframes of sample.threads
                    for i in [curframes.length-1..0]
                        if frameid == curframes[i]
                            ret.totsamples += 1
                            if curframes[i-1]?
                                increaseStats(ret.callees, curframes[i-1])
                            if curframes[i+1]?
                                increaseStats(ret.callers, curframes[i+1])
            normalize = (array) ->
                array = _.values(array)
                for c in array
                    c.percent = c.samples * 100.0 / ret.totsamples
                array.sort (a,b) -> b.percent - a.percent
                return array
            ret.callers = normalize(ret.callers)
            ret.callees = normalize(ret.callees)
            return ret

        profileToCpu: ({frames, samples}) ->
            ret = {
                cpu: {key:"cpu", values:[]}
                mem: {key:"mem", values:[]}
                load: {key:"load", values:[]}
               }
            start = samples[0].time
            lastsecond = start
            samplepersecond = 0
            maxload = 0
            if samples.length > 1000
                skips = samples.length/1000
            else
                skips = 0
            toskip = skips
            cursamplepersecond = {x:0, y:0}
            for sample in samples
                totcpu = 0
                for cpu, i in sample.cpu
                    totcpu += cpu
                samplepersecond += 1
                second = Math.floor(sample.time)
                if second > lastsecond
                    cursamplepersecond = x:Math.floor(sample.time - start), y: samplepersecond
                    if skips == 0
                        ret.load.values.push cursamplepersecond
                    if samplepersecond > maxload
                        maxload = samplepersecond
                    samplepersecond = 0
                    lastsecond = second
                toskip -= 1
                if toskip <= 0
                    toskip = skips
                    if skips != 0 and ret.load.values[ret.load.values.length-1] != cursamplepersecond
                        ret.load.values.push cursamplepersecond
                    ret.cpu.values.push x:sample.time - start, y:totcpu
                    ret.mem.values.push x:sample.time - start, y:sample.mem.percent
            for s in ret.load.values
                s.y = s.y * 100 / maxload
            return _.values(ret)
        }
