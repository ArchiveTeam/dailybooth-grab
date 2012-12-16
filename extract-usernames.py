#!/usr/bin/env python
import gzip
import re
import sys

USERNAME_LINK_RE = re.compile(r'<a href="/([-_A-Za-z0-9]+)">([-_A-Za-z0-9]+)</a>')

seen = set()

print >> sys.stderr, "Extracting usernames from %s" % sys.argv[1]

with open(sys.argv[2], "w") as f_out:
  f_in = gzip.open(sys.argv[1])
  for line in f_in:
    for a, b in USERNAME_LINK_RE.findall(line):
      if a == b and not a in seen:
        seen.add(a)
        print >> f_out, a
        sys.stderr.write("\rFound: %d" % len(seen))
  f_in.close()

n = len(seen)
print >> sys.stderr, "\rExtracted %d username%s." % (n, ("" if n==1 else "s"))

