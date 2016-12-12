
This plugin implements a profiler for buildbot master.

- It uses statistical profiling loosely based on plop https://github.com/bdarnell/plop
- Suitable for prod as statistical profiling is very low overhead
- Profiles all threads including main thread and db threads
- Removes noise samples when the threads are actually in the main loop
- In-browser UI based on nvd3 and d3-flame-graph
- Show cpu and memory percent over time
- flame graph can be restricted to a subset of the trace
- Detailed caller/callee are displayed when clicking on a function


Usage
=====

installation:

.. code:: bash

    pip install buildbot_profiler

then in master.cfg:

.. code:: python

    c['www']['plugins']['profiler'] = True

Standalone Viewer
=================

A standalone viewer is provided for offline browse of user submitted profiles.

.. code:: bash

    bbprofiler

Then you can open your browser on http://localhost:8080

Screenshot
==========

.. image:: https://raw.githubusercontent.com/tardyp/buildbot_profiler/master/screenshot.png
