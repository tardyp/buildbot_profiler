#!/usr/bin/env python
try:
    from buildbot_pkg import setup_www_plugin
except ImportError:
    import sys
    print >> sys.stderr, "Please install buildbot_pkg module in order to install that package, or use the pre-build .whl modules available on pypi"
    sys.exit(1)

setup_www_plugin(
    name='buildbot-profiler',
    description='"Profiler for buildbot master and its UI"',
    long_description=open('README.rst').read(),
    author=u'Buildbot contributors',
    author_email=u'devel@buildbot.net',
    url='https://github.com/tardyp/buildbot_profiler',
    license='GNU GPL',
    version='1.2.2',
    packages=['buildbot_profiler'],
    install_requires=[
        'klein', 'psutil'
    ],
    package_data={
        '': [
            'VERSION',
            'static/*'
        ]
    },
    entry_points="""
        [buildbot.www]
        profiler= buildbot_profiler:ep
        [buildbot.util]
        ProfilerService= buildbot_profiler.api:ProfilerService
        [console_scripts]
        bbprofiler=buildbot_profiler.app:main
    """,
)
