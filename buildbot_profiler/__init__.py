from buildbot.www.plugin import Application

from .api import Api


# create the interface for the setuptools entry point
ep = Application(__name__, "Buildbot profiler")
api = Api(ep)
ep.resource.putChild("api", api.app.resource())
