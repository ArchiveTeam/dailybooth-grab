import time
import os
import os.path
import functools
import shutil
import glob
import json
from distutils.version import StrictVersion

from tornado import gen, ioloop
from tornado.httpclient import AsyncHTTPClient, HTTPRequest

import seesaw
from seesaw.project import *
from seesaw.config import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.tracker import *


if StrictVersion(seesaw.__version__) < StrictVersion("0.0.10"):
  raise Exception("This pipeline needs seesaw version 0.0.10 or higher.")


USER_AGENT = "Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/533.20.25 (KHTML, like Gecko) Version/5.0.4 Safari/533.20.27"
VERSION = "20121228.01"

class ConditionalTask(Task):
  def __init__(self, condition_function, inner_task):
    Task.__init__(self, "Conditional")
    self.condition_function = condition_function
    self.inner_task = inner_task
    self.inner_task.on_complete_item += self._inner_task_complete_item
    self.inner_task.on_fail_item += self._inner_task_fail_item

  def enqueue(self, item):
    if self.condition_function(item):
      self.inner_task.enqueue(item)
    else:
      item.log_output("Skipping tasks for this item.")
      self.complete_item(item)

  def _inner_task_complete_item(self, task, item):
    self.complete_item(item)
  
  def _inner_task_fail_item(self, task, item):
    self.fail_item(item)

  def fill_ui_task_list(self, task_list):
    self.inner_task.fill_ui_task_list(task_list)

  def __str__(self):
    return "Conditional(" + str(self.inner_task) + ")"

class GetIdForUsername(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, "GetIdForUsername")

  def enqueue(self, item):
    self.start_item(item)
    self.request(item)

  def request(self, item):
    user_name = item["item_name"]

    http_client = AsyncHTTPClient()
    item.log_output("Finding ID for username %s: " % user_name, full_line=False)
    api_url = "http://dailybooth.com/%s" % user_name

    http_client.fetch(api_url, functools.partial(self.handle_response, item), user_agent=USER_AGENT, validate_cert=False)

  def handle_response(self, item, response):
    if response.code == 200:
      html = response.body

      user_id = re.search(r'"follow_user not_following disabled big".+data-user_id="([0-9]+)"', html)

      if user_id:
        user_id = user_id.group(1)
        item.log_output("'%s'\n" % user_id, full_line=False)
        item["dailybooth_user_id"] = user_id
        self.complete_item(item)

      else:
        item.log_output("private or not found.\n", full_line=False)
        self.complete_item(item)

    elif response.code == 503:
      item.log_output("Rate limited. Waiting for 30 seconds...")
      ioloop.IOLoop.instance().add_timeout(datetime.timedelta(seconds=30), functools.partial(self.request, item))

    elif response.code == 404:
      item.log_output("not found (response code %d).\n" % response.code, full_line=False)
      self.complete_item(item)

    else:
      item.log_output("unknown error (response code %d).\n" % response.code, full_line=False)
      self.fail_item(item)

class PrepareDirectories(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, "PrepareDirectories")

  def process(self, item):
    item_name = item["item_name"]
    dirname = "/".join(( item["data_dir"], item_name ))

    if os.path.isdir(dirname):
      shutil.rmtree(dirname)

    os.makedirs(dirname + "/files")

    if "dailybooth_user_id" in item:
      user_id = item["dailybooth_user_id"]
    else:
      user_id = "notfound"
    username = item_name

    item["item_dir"] = dirname
    item["warc_file_base"] = "dailybooth.com-2-user-%s-%s-%s" % (username, user_id, time.strftime("%Y%m%d-%H%M%S"))

    open("%(item_dir)s/%(warc_file_base)s.warc.gz" % item, "w").close()

class MoveFiles(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, "MoveFiles")

  def process(self, item):
    os.rename("%(item_dir)s/%(warc_file_base)s.warc.gz" % item,
              "%(data_dir)s/%(warc_file_base)s.warc.gz" % item)

    shutil.rmtree("%(item_dir)s" % item)

def calculate_item_id(item):
  if "dailybooth_data" in item:
    dd = item["dailybooth_data"]
    d = {}
    d["user_id"] = dd["user_id"]
    d["username"] = dd["username"]
    if "details" in dd and "name" in dd["details"]:
      d["name"] = dd["details"]["name"]
    d["picture_count"] = dd["picture_count"]
    d["followers_count"] = dd["followers_count"]
    d["following_count"] = dd["following_count"]
    return d
  elif "dailybooth_user_id" in item:
    return item["dailybooth_user_id"]
  else:
    return None

class CurlUpload(ExternalProcess):
  def __init__(self, target, filename):
    args = [
      "curl",
      "--fail",
      "--output", "/dev/null",
      "--connect-timeout", "60",
      "--speed-limit", "1",        # minimum upload speed 1B/s
      "--speed-time", "900",       # stop if speed < speed-limit for 900 seconds
      "--header", "X-Curl-Limits: inf,1,900",
      "--write-out", "Upload server: %{url_effective}\\n",
      "--location",
      "--upload-file", filename,
      target
    ]
    ExternalProcess.__init__(self, "CurlUpload",
        args = args,
        max_tries = None)



project = Project(
  title = "DailyBooth",
  project_html = """
    <img class="project-logo" alt="DailyBooth logo" src="http://archiveteam.org/images/2/2f/Dailybooth-logo.png" />
    <h2>DailyBooth <span class="links"><a href="http://dailybooth.com/">Website</a> &middot; <a href="http://tracker.archiveteam.org/dailybooth/">Leaderboard</a></span></h2>
    <p><i>DailyBooth</i>, launched in 2009, is closing. We archive the member photos.</p>
  """,
  utc_deadline = datetime.datetime(2012,12,31, 23,59,0)
)

pipeline = Pipeline(
# ExternalProcess("User discovery 1", ["./discover-dailybooth-2.py"]),
# ExternalProcess("User discovery 2", ["./discover-dailybooth-2.py"]),
# ExternalProcess("User discovery 3", ["./discover-dailybooth-2.py"])
  GetItemFromTracker("http://tracker.archiveteam.org/dailybooth", downloader, VERSION),
  GetIdForUsername(),
  PrepareDirectories(),
  ConditionalTask(lambda item: ("dailybooth_user_id" in item),
    WgetDownload([ "./wget-lua",
        "-U", USER_AGENT,
        "-nv",
        "-o", ItemInterpolation("%(item_dir)s/wget.log"),
        "--no-check-certificate",
        "--directory-prefix", ItemInterpolation("%(item_dir)s/files"),
        "--force-directories",
        "--adjust-extension",
        "-e", "robots=off",
        "--page-requisites", "--span-hosts",
        "--lua-script", "dailybooth-noapi.lua",
        "--reject-regex", "api.mixpanel.com|www.facebook.com|platform.twitter.com",
        "--timeout", "60",
        "--tries", "20",
        "--waitretry", "5",
        "--warc-file", ItemInterpolation("%(item_dir)s/%(warc_file_base)s"),
        "--warc-header", "operator: Archive Team",
        "--warc-header", "dailybooth-dld-script-version: " + VERSION,
        "--warc-header", ItemInterpolation("dailybooth-user-id: %(dailybooth_user_id)s"),
        "--warc-header", ItemInterpolation("dailybooth-username: %(item_name)s"),
        ItemInterpolation("http://dailybooth.com/%(item_name)s")
      ],
      max_tries = 2,
      accept_on_exit_code = [ 0, 4, 6, 8 ],
    ),
  ),
  ConditionalTask(lambda item: ("dailybooth_user_id" in item),
    ExternalProcess("ExtractUsernames",
      ["./extract-usernames.py",
       ItemInterpolation("%(item_dir)s/%(warc_file_base)s.warc.gz"),
       ItemInterpolation("%(data_dir)s/%(warc_file_base)s.usernames.txt")])
  ),
  PrepareStatsForTracker(
    defaults = { "downloader": downloader, "version": VERSION },
    file_groups = {
      "data": [ ItemInterpolation("%(item_dir)s/%(warc_file_base)s.warc.gz") ]
    },
    id_function = calculate_item_id
  ),
  MoveFiles(),
  ConditionalTask(lambda item: ("dailybooth_user_id" in item),
    LimitConcurrent(NumberConfigValue(min=1, max=4, default="1", name="shared:rsync_threads", title="Rsync threads", description="The maximum number of concurrent uploads."),
      RsyncUpload(
        target = ConfigInterpolation("216.245.195.218::dailybooth/%s/", downloader),
        target_source_path = ItemInterpolation("%(data_dir)s/"),
        files = [
          ItemInterpolation("%(data_dir)s/%(warc_file_base)s.warc.gz"),
          ItemInterpolation("%(data_dir)s/%(warc_file_base)s.usernames.txt")
        ],
        extra_args = [
          "--recursive",
          "--partial",
          "--partial-dir", ".rsync-tmp"
        ]
      ),
    ),
  ),
  SendDoneToTracker(
    tracker_url = "http://tracker.archiveteam.org/dailybooth",
    stats = ItemValue("stats")
  )
)

