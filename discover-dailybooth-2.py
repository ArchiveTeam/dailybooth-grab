#!/usr/bin/env python

import json
import re
import time
import urllib
import sys
import os

from tornado import ioloop, httpclient, gen


# kill the old version (didn't stop on errors)
os.system('pkill -f discover-dailybooth.py')


USER_AGENT = "Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/533.20.25 (KHTML, like Gecko) Version/5.0.4 Safari/533.20.27"
http_client = httpclient.HTTPClient()
ahttp_client = httpclient.AsyncHTTPClient()

print "Loading task..."
res = http_client.fetch("http://tracker.archiveteam.org:8126/request", method="POST", body="version=2")
task = json.loads(res.body)
# task = { "prefix": "10000", "usernames": ["xyz","api","charles"] }

if task["prefix"] == None:
  print "No task."
  exit()

usernames = task["usernames"]
prefix = task["prefix"]
print "Task %s" % prefix


usernames_found = set()
queue = [ (5,i) for i in range(0,100) ]
running = [ 0 ]

def handle_request(response):
  if response.code == 302:
    # redirect to real username!
    usernames_found.add(response.headers['Location'].split("/")[-1])
  elif response.code >= 500 and response.code <= 599:
    print "\nError %d" % response.code
    if response.request.i[0] > 0:
      queue.append((response.request.i[0] - 1, response.request.i[1]))

  running[0] = running[0] - 1
  next_from_queue()

def next_from_queue():
  if len(queue) > 0:
    tries, i = queue.pop()
    sys.stdout.write("\r%d  " % i)
    sys.stdout.flush()

    req = httpclient.HTTPRequest(
        ("http://dailybooth.com/%s/%s%02d" % (usernames[i % len(usernames)], prefix, i)),
        connect_timeout=10, request_timeout=30,
        follow_redirects=False,
        user_agent=USER_AGENT)
    req.i = (tries, i)
    ahttp_client.fetch(req, handle_request)
    running[0] = running[0] + 1

  elif running[0] == 0:
    ioloop.IOLoop.instance().stop()

# next_from_queue()
next_from_queue()
next_from_queue()

ioloop.IOLoop.instance().start()


sys.stdout.write("\n")

usernames_found = [ u for u in usernames_found ]
# print usernames_found

print
print "Submitting results (%d usernames)..." % (len(usernames_found))
json_body = json.dumps({ "prefix": task["prefix"], "usernames_found": usernames_found })
# print json_body
res = http_client.fetch("http://tracker.archiveteam.org:8126/submit", method="POST",
                        body=json_body, headers={"Content-Type": "application/json"})


