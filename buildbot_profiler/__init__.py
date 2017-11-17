from buildbot.www.plugin import Application
from buildbot.util import unicode2bytes

from .api import Api


# create the interface for the setuptools entry point
ep = Application(__name__, "Buildbot profiler")
api = Api(ep)
ep.resource.putChild(unicode2bytes("api"), api.app.resource())
