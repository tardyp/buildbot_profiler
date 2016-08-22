from __future__ import with_statement

import json
import signal
import sys
import thread
import time
from signal import ITIMER_PROF
from signal import ITIMER_REAL
from signal import ITIMER_VIRTUAL
from signal import setitimer

from future.utils import iteritems
from klein import Klein
from twisted.internet import defer

import psutil

# waiting functions we should not take in the profile, as those are evidence that the thread is idle
BLACKLIST = [
    ("threading.py", "wait"),
    ("epollreactor.py", "doPoll"),
]


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
            return

        current_tid = thread.get_ident()
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
            mem=dict(psutil.virtual_memory().__dict__)))

        end = time.time()
        self.samples_taken += 1
        self.sample_time += (end - start)

    def asJson(self):
        self.paused = True
        r = json.dumps(dict(
            gatherperiod=self.gatherperiod,
            frequency=self.frequency,
            frames=self.frames,
            samples=self.samples
        ))
        self.paused = False
        return r


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
        self.gatherperiod = int(request.args.get('gatherperiod', [self.gatherperiod])[0])
        self.frequency = int(request.args.get('frequency', [self.frequency])[0])
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
