import os
import sys

from twisted.internet import reactor
from twisted.python import log
from twisted.web.server import Site

from buildbot_profiler import ep


def main():
    port = os.environ.get("PORT", 8080)

    print "running on http://localhost:{}".format(port)
    log.startLogging(sys.stdout)
    ep.resource.putChild('profiler', ep.resource)
    reactor.listenTCP(port, Site(ep.resource), interface='localhost')
    reactor.run()
