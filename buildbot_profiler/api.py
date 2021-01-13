from __future__ import with_statement

import datetime
import json
import os
import signal
import sys
import threading
import time
from signal import ITIMER_PROF, ITIMER_REAL, ITIMER_VIRTUAL, setitimer

import psutil
from buildbot import config
from buildbot.util import toJson
from buildbot.util.service import BuildbotService
from future.utils import iteritems
from klein import Klein
from twisted.internet import defer, reactor

# waiting functions we should not take in the profile, as those are evidence that the thread is idle
BLACKLIST = [
    ("threading.py", "wait"),
    ("epollreactor.py", "doPoll"),
]
try:
    get_ident = threading.get_ident
except AttributeError:
    import thread
    get_ident = thread.get_ident


class Collector(object):
    MODES = {
        'prof': (ITIMER_PROF, signal.SIGPROF),
        'virtual': (ITIMER_VIRTUAL, signal.SIGVTALRM),
        'real': (ITIMER_REAL, signal.SIGALRM),
    }

    def __init__(self, frequency=100, gatherperiod=30, mode='virtual'):
        self.frequency = frequency
        self.gatherperiod = gatherperiod
        self.mode = mode
        assert mode in Collector.MODES
        timer, sig = Collector.MODES[self.mode]
        signal.signal(sig, self.handler)
        signal.siginterrupt(sig, False)
        self.finish_callback = lambda: None
        self.reset()

    def reset(self):
        self.samples = list()
        self.frames = list()
        self.frames_hash = dict()
        self.start_time = time.time()
        self.stopping = False
        self.stopped = True

        self.samples_taken = 0
        self.sample_time = 0

    def start(self):
        self.stopping = False
        self.paused = False
        self.stopped = False
        self.stoptime = time.time() + self.gatherperiod
        timer, sig = Collector.MODES[self.mode]
        interval = 1. / self.frequency
        setitimer(timer, interval, interval)

    def stop(self):
        self.stopping = True
        self.wait()

    def wait(self):
        while not self.stopped:
            pass  # need busy wait; ITIMER_PROF doesn't proceed while sleeping

    def getFrameid(self, filename, lineno, name):
        """Store the frames data per id to save memory"""
        filename = filename[-20:]
        k = filename + str(lineno) + name
        if k in self.frames_hash:
            return self.frames_hash[k]
        i = len(self.frames)
        self.frames.append((filename, lineno, name))
        self.frames_hash[k] = i
        return i

    def handler(self, sig, current_frame):
        if self.paused:
            return
        start = time.time()
        if self.stoptime < start or self.stopping:
            setitimer(Collector.MODES[self.mode][0], 0, 0)
            self.stopped = True
            reactor.callFromThread(self.finish_callback)
            return

        current_tid = get_ident()
        threads = {}

        for tid, frame in iteritems(sys._current_frames()):
            if tid == current_tid:
                frame = current_frame
            frames = []
            shall_ignore = False
            for fn, co_name in BLACKLIST:
                if (frame and frame.f_code.co_filename.endswith(fn) and
                        frame.f_code.co_name == co_name):
                    shall_ignore = True
                    continue
            if shall_ignore:
                continue
            while frame is not None:
                code = frame.f_code
                frames.append(self.getFrameid(code.co_filename, frame.f_lineno, code.co_name))
                frame = frame.f_back
            threads[tid] = frames

        self.samples.append(dict(
            time=start,
            threads=threads,
            cpu=psutil.cpu_percent(percpu=True),
            mem=psutil.virtual_memory()._asdict()))

        end = time.time()
        self.samples_taken += 1
        self.sample_time += (end - start)

    def asJson(self):
        return json.dumps(self.asDict())

    def asDict(self):
        self.paused = True
        r = dict(
            gatherperiod=self.gatherperiod,
            frequency=self.frequency,
            frames=self.frames,
            samples=self.samples
        )
        self.paused = False
        return r


class ProfilerService(BuildbotService):
    name = "ProfilerService"

    def checkConfig(self, frequency=100, gatherperiod=30 * 60, mode='virtual',
                    basepath=None, wantBuilds=100):
        BuildbotService.checkConfig(self)
        if mode not in Collector.MODES:
            config.error("mode should be in {} while it is {}".format(Collector.MODES, mode))
        self.collector = None

    def reconfigService(self, frequency=100, gatherperiod=30 * 60, mode='virtual',
                        basepath=None, wantBuilds=100):
        BuildbotService.reconfigService(self)
        if self.collector is not None:
            self.collector.stop()
            self.collector.reset()
        if basepath is None:
            basepath = os.path.join(self.master.basedir, "prof_")
        self.basepath = basepath
        self.wantBuilds = wantBuilds
        self.collector = Collector(frequency=frequency, gatherperiod=gatherperiod, mode=mode)
        self.collector.finish_callback = self.finished
        print("starting profiler")
        self.collector.start()

    def stopService(self):
        BuildbotService.stopService(self)
        if self.collector is not None:
            print("stopping profiler")
            collector, self.collector = self.collector, None
            collector.stop()

    @defer.inlineCallbacks
    def finished(self):
        if self.collector is not None:
            data = self.collector.asDict()
            self.collector.reset()
            self.collector.start()
            if self.wantBuilds:
                data['builds'] = yield self.master.data.get(
                    ("builds",), order=["-buildid"], limit=self.wantBuilds)
                data['builds'] = data['builds'].data
            with open(self.basepath + datetime.datetime.now().isoformat() + ".json", "w") as o:
                o.write(json.dumps(data, default=toJson))


class Api(object):
    app = Klein()
    gatherperiod = 30
    frequency = 100
    mode = "virtual"

    def __init__(self, ep):
        self.ep = ep
        self.collector = None
        self.json = None

    @app.route("/start", methods=['GET'])
    def startProfile(self, request):
        if self.collector is not None:
            request.setResponseCode(409)
            return defer.succeed("already started")
        self.gatherperiod = int(request.args.get(b'gatherperiod', [self.gatherperiod])[0])
        self.frequency = int(request.args.get(b'frequency', [self.frequency])[0])
        self.collector = Collector(self.frequency, self.gatherperiod, self.mode)
        self.collector.start()
        return defer.succeed("OK")

    @app.route("/stop", methods=['GET'])
    def stopProfile(self, request):
        if self.collector is None:
            request.setResponseCode(409)
            return defer.succeed("not started")
        self.collector.stop()
        self.json = self.collector.asJson()
        self.collector = None
        return defer.succeed("OK")

    @app.route("/status", methods=['GET'])
    def status(self, request):
        request.setHeader('Content-Type', 'application/json')
        if self.collector is not None and self.collector.stopped:
            self.json = self.collector.asJson()
            self.collector = None
        status = dict(
            gatherperiod=self.gatherperiod,
            frequency=self.frequency,
            profile_available=False,
            started=False)
        if self.collector is not None:
            status.update(dict(
                started=True,
                num_samples=len(self.collector.samples),
                remaining=self.collector.stoptime - time.time()
            ))
        if self.json is not None:
            status['profile_available'] = True
        return defer.succeed(json.dumps(status))

    @app.route("/profiles", methods=['GET'])
    def listProfiles(self, request):
        request.setHeader('Content-Type', 'application/json')
        if self.collector is not None:
            return defer.succeed(self.collector.asJson())
        elif self.json:
            return defer.succeed(self.json)
        return defer.succeed("{}")
