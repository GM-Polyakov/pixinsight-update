#!/usr/bin/env python3
"""A stand-in for PixInsight's download service, for tests on this computer only.

It listens on 127.0.0.1 and imitates what is known of https://pixinsight.com/dist/:
a sign-in form that posts user_name and user_password to browser.php, and a
refusal page that says ACCESS DENIED with response code 200.

What the real service shows after sign-in is not known yet, so the stand-in can
imitate three layouts, and two ways of remembering a sign-in:

  --layout links     one page with a link per installer
  --layout folders   a file browser: folder links, installers at the bottom
  --layout forms     one form with hidden fields and a list of installers
  --layout real      what the real service turned out to do (seen 2026-11-24):
                     one long page; each installer is a link to
                     download_inst.php?session_id=...&file_id=..., with the file
                     name only in the link text and a SHA-1 checksum in the same
                     table row; sign-in sets a cookie named PHPSESSID; a request
                     without that cookie answers 302 and points at the sign-in
                     page. That the session value in the links equals the cookie
                     is an assumption, which the probe's first route tests.

  --session cookie   the sign-in is remembered by a cookie
  --session none     nothing is remembered: every request must post the details
                     (the "real" layout ignores this: its links carry the session)

  --cdn none         download_inst.php sends the file itself
  --cdn same         it answers 302 and points at another address on this server
  --cdn other        it answers 302 and points at another host name (localhost)

  --refuse-curl      answer 406 to a client that calls itself curl, as the real
                     site does
  --only-old         list no installer newer than 1.9.3
  --newest VERSION   also list installers of this made-up version (the
                     rehearsal uses 9.9.9, newer than any real PixInsight)
  --only-version V   list installers of this one version and nothing else (the
                     Windows rehearsal gives the installed version, so that
                     there is nothing newer whichever PixInsight is installed)
  --bad-sha1         show a checksum on the page that the file does not have
  --slow-ms N        wait N milliseconds between pieces of a download
  --drop-first-mb N  break the first download off after N megabytes
  --strict-agent     accept a session only from the client name that signed in

The account is made up, and the "installers" are files of zeros that only start
as real ones do: with the two bytes of a Windows program where the name ends in
.exe, and with the four bytes of a macOS installer package everywhere else. The
Windows helper looks at the first two bytes of its download, as the macOS helper
looks at the first four. Each of the two kinds has its own SHA-1 checksum.

    user name:  standin-user
    password:   standin-pass!1

Usage:  python3 dist-server.py [--port 8719] [--layout links] [--session cookie]
                               [--cdn none] [--refuse-curl] [--strict-agent] [--size-mb 8] [--log FILE]
"""

import argparse
import hashlib
import html
import secrets
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER = "standin-user"
PASSWORD = "standin-pass!1"

FILES = [
    ("PixInsight/1.9.4/macosx", "PI-macosx-arm64-1.9.4-20260901-c.pkg"),
    ("PixInsight/1.9.4/macosx", "PI-macosx-x64-1.9.4-20260901-c.pkg"),
    ("PixInsight/1.9.3/macosx", "PI-macosx-x64-1.9.3-20250402-c.pkg"),
    ("PixInsight/1.9.4/windows", "PI-windows-x64-1.9.4-20260901-c.exe"),
    ("PixInsight/1.9.4/linux", "PI-linux-x64-1.9.4-20260901-c.tar.xz"),
]

REAL_FILES = [
    "PI-windows-x64-gpu-1.9.6-20261119-c.exe",
    "PI-macosx-x64-1.9.6-20261119-c.pkg",
    "PI-macosx-arm64-1.9.6-20261119-c.pkg",
    "PI-linux-x64-gpu-1.9.6-20261119-c.tar.xz",
    "PI-windows-x64-1.9.4-20260621-c.exe",
    "PI-macosx-x64-1.9.4-20260621-c.pkg",
    "PI-macosx-arm64-1.9.4-20260621-c.pkg",
    "PI-macosx-x64-1.9.3-20250402-c.pkg",
    "PI-macosx-x64-1.8.9-3-20241124-c.pkg",
]

ARGS = None
SESSIONS = set()
SESSION_AGENT = {}
CDN_TOKENS = {}
# The SHA-1 checksum of each kind of stand-in installer, by its first bytes.
FILE_SHA1 = {}
DROPPED = [False]


def file_id(name):
    return hashlib.sha1(name.encode("utf-8")).hexdigest()


def file_start(name):
    """The first bytes of the stand-in installer of this name: those of a Windows
    program if the name ends in .exe, otherwise those of a macOS installer package."""
    return b"MZ" if name.endswith(".exe") else b"xar!"

NAV = '<p><a href="/">Home</a> | <a href="/dist/reset_password.html">Forgot your password or username?</a></p>'


def page(title, body):
    return ("<!DOCTYPE html><html><head><title>PixInsight &mdash; " + title + "</title></head><body>"
            + NAV + body + "</body></html>").encode("utf-8")


def signin_page():
    return page("Software Distribution",
                "<h1>Software Distribution</h1><p>Please log in with your user account data.</p>"
                '<form action="browser.php" method="post">'
                '<input type="text" name="user_name" id="user_name" value="">'
                '<input type="password" name="user_password" id="user_password" value="">'
                '<input type="checkbox" name="show_passwords">'
                '<input type="submit" value="&gt; Login"><input type="reset" value="Reset"></form>')


def denied_page():
    return page("Software Distribution",
                "<h1>ACCESS DENIED</h1><p>Incorrect user credentials.</p><p><a href=\"index.html\">Try again?</a></p>")


def welcome():
    return ("<p>Welcome, Standin Q. Person (standin@example.org). Customer 12345678.</p>"
            '<p><a href="browser.php?action=logout">Logout</a></p>')


def real_listing(session):
    def link(script, name, text):
        return '<a href="%s?session_id=%s&amp;file_id=%s">%s</a>' % (script, session, file_id(name), text)
    names = [n for n in REAL_FILES if not ARGS.only_old or "1.9.3" in n or "1.8.9" in n]

    def shown_sha1(name):
        # Each row shows the checksum of its own file, or that checksum backwards.
        sha1 = FILE_SHA1[file_start(name)]
        return sha1[::-1] if ARGS.bad_sha1 else sha1
    rows = "".join("<tr><td>%s</td><td>%d.000</td><td>2026 Nov 19 21:05:45</td><td>H</td>"
                   "<td>PixInsight stand-in<br>Core version (commercial)</td><td>%s</td></tr>"
                   % (link("download_inst.php", n, n), ARGS.size_mb, shown_sha1(n))
                   for n in names)
    other = "".join("<tr><td>%s</td><td>2.80 GiB</td><td>1.0.0</td></tr>" % link("download_xpsd.php", "catalog-%d" % i, "Download")
                    for i in range(3))
    return page("Software Distribution",
                "<h2>PixInsight Software Distribution</h2>"
                "<p>You have logged in 16 times. Previous login was on 2026/11/24 from 203.0.113.77.</p>"
                "<p>User: Standin Q. Person (standin@example.org). Customer 12345678.</p>"
                '<p><a href="/dist/browser.php?action=logout">Logout</a></p>'
                '<form method="post" action="email_address_change_request.php">'
                '<input type="text" name="new_email_address" value=""><input type="submit" value="&gt; Change"></form>'
                '<p><a href="license_reactivation_request.php">Request License Reactivation</a></p>'
                "<h4>Gaia Database Files</h4><table>" + other + "</table>"
                "<h4>PixInsight Installation Files</h4><table>" + rows + "</table>")


def listing(query):
    size = ARGS.size_mb
    if ARGS.layout == "links":
        rows = "".join(
            '<tr><td>%s</td><td><a href="download.php?file=%s">%s</a></td><td>%d MB</td></tr>'
            % (html.escape(folder), name, name, size) for folder, name in FILES)
        return page("Software Distribution", "<h1>Software Distribution</h1>" + welcome()
                    + "<h2>PixInsight 1.9.4 Lockhart</h2><table>" + rows + "</table>")

    if ARGS.layout == "forms":
        options = "".join('<option value="%s">%s</option>' % (name, name) for _, name in FILES)
        return page("Software Distribution", "<h1>Software Distribution</h1>" + welcome()
                    + '<form action="download.php" method="post">'
                    + '<input type="hidden" name="user_name" value="%s">' % USER
                    + '<input type="hidden" name="user_password" value="%s">' % html.escape(PASSWORD)
                    + '<select name="file">' + options + "</select>"
                    + '<input type="submit" name="go" value="Download"></form>')

    # folders
    here = query.get("dir", [""])[0].strip("/")
    folders, files = set(), []
    for folder, name in FILES:
        if folder == here:
            files.append(name)
        elif here == "" or folder.startswith(here + "/"):
            rest = folder[len(here):].strip("/")
            folders.add(rest.split("/")[0])
    rows = ""
    for f in sorted(folders):
        target = (here + "/" + f).strip("/")
        rows += '<tr><td><a href="browser.php?dir=%s">%s</a></td><td>folder</td></tr>' % (
            urllib.parse.quote(target, safe=""), html.escape(f))
    for name in files:
        rows += '<tr><td><a href="download.php?dir=%s&amp;file=%s">%s</a></td><td>%d MB</td></tr>' % (
            urllib.parse.quote(here, safe=""), name, name, size)
    return page("Software Distribution", "<h1>Software Distribution</h1>" + welcome()
                + "<h2>" + html.escape(here or "All products") + "</h2><table>" + rows + "</table>")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def note(self, what):
        if ARGS.log:
            with open(ARGS.log, "a") as f:
                f.write("%s %s %s  agent=%s  %s\n" % (time.strftime("%H:%M:%S"), self.command, self.path,
                                                     self.headers.get("User-Agent", "-"), what))

    def send_page(self, body, cookie=None, cookie_name="DISTSESSION"):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=UTF-8")
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header("Set-Cookie", "%s=%s; path=/" % (cookie_name, cookie))
        self.end_headers()
        self.wfile.write(body)

    def bounce(self):
        """What the real service does with a request it does not recognise:
        point at the sign-in page and hand out a fresh, signed-out session."""
        self.send_response(302)
        self.send_header("Location", "./index.html")
        self.send_header("Set-Cookie", "PHPSESSID=%s; path=/" % secrets.token_hex(16))
        self.send_header("Content-Type", "text/html; charset=UTF-8")
        self.send_header("Content-Length", "0")
        self.end_headers()
        return None

    def real_cookie(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            name, _, value = part.strip().partition("=")
            if name == "PHPSESSID":
                return value
        return ""

    def send_plain(self, code, text):
        body = (text + "\n").encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=UTF-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return None

    def send_file(self, name):
        """The stand-in installer: the bytes that start a real file of its kind, then zeros."""
        start = file_start(name)
        size = ARGS.size_mb * 1048576
        first, last = 0, size - 1
        ranged = False
        header = self.headers.get("Range") or ""
        if header.startswith("bytes="):
            a, _, b = header[6:].partition("-")
            if a.isdigit():
                first = int(a)
                last = min(int(b), size - 1) if b.isdigit() else size - 1
                ranged = first <= last
        self.note("download started: %s%s" % (name, " (bytes %d-%d)" % (first, last) if ranged else ""))
        self.send_response(206 if ranged else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % name)
        self.send_header("Accept-Ranges", "bytes")
        if ranged:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (first, last, size))
        else:
            first, last = 0, size - 1
        self.send_header("Content-Length", str(last - first + 1))
        self.end_headers()
        sent = 0
        try:
            pos = first
            while pos <= last:
                n = min(65536, last - pos + 1)
                chunk = bytearray(n)
                for i in range(len(start)):
                    if pos <= i < pos + n:
                        chunk[i - pos] = start[i]
                self.wfile.write(bytes(chunk))
                pos += n
                sent += n
                if ARGS.slow_ms:
                    time.sleep(ARGS.slow_ms / 1000.0)
                if ARGS.drop_first_mb and not DROPPED[0] and sent >= ARGS.drop_first_mb * 1048576:
                    DROPPED[0] = True
                    self.note("download broken off on purpose after %d bytes" % sent)
                    self.close_connection = True
                    return None
            self.note("download complete: %d bytes" % sent)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # The third of these is how Windows can report a client that has gone.
            self.note("download stopped by the client after %d bytes" % sent)
            self.close_connection = True
        return None

    def form(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        return urllib.parse.parse_qs(raw, keep_blank_values=True)

    def has_cookie(self):
        if ARGS.session != "cookie":
            return False
        for part in (self.headers.get("Cookie") or "").split(";"):
            name, _, value = part.strip().partition("=")
            if name == "DISTSESSION" and value in SESSIONS:
                return True
        return False

    @staticmethod
    def has_details(form):
        return form.get("user_name", [""])[0] == USER and form.get("user_password", [""])[0] == PASSWORD

    def handle_any(self, form):
        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query, keep_blank_values=True)
        path = url.path
        posted = "user_name" in form or "user_password" in form

        if ARGS.refuse_curl and (self.headers.get("User-Agent") or "").lower().startswith("curl/"):
            self.note("refused: the client calls itself curl")
            return self.send_plain(406, "Not Acceptable")

        if path.startswith("/cdn/"):
            parts = path.split("/")
            name = CDN_TOKENS.get(parts[2] if len(parts) > 3 else "")
            if not name or parts[3] != name:
                self.note("file address not valid")
                return self.send_plain(403, "Forbidden")
            return self.send_file(name)

        if ARGS.layout == "real" and path == "/dist/download_inst.php":
            session = query.get("session_id", [""])[0]
            wanted = query.get("file_id", [""])[0]
            names = [n for n in REAL_FILES if file_id(n) == wanted]
            cookie = self.real_cookie()
            if cookie not in SESSIONS or session != cookie or not names:
                self.note("download bounced to the sign-in page: %s"
                          % ("no valid session cookie" if cookie not in SESSIONS else "the link is not this session's"))
                return self.bounce()
            if ARGS.strict_agent and SESSION_AGENT.get(cookie) != (self.headers.get("User-Agent") or ""):
                self.note("download bounced to the sign-in page: not the client name that signed in")
                return self.bounce()
            if ARGS.cdn == "none":
                return self.send_file(names[0])
            token = secrets.token_hex(20)
            CDN_TOKENS[token] = names[0]
            host = "localhost" if ARGS.cdn == "other" else "127.0.0.1"
            target = "http://%s:%d/cdn/%s/%s" % (host, ARGS.port, token, names[0])
            self.note("download redirected to %s" % ("another host name" if ARGS.cdn == "other" else "another address here"))
            self.send_response(302)
            self.send_header("Location", target)
            self.send_header("Content-Type", "text/html; charset=UTF-8")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None

        if ARGS.layout == "real" and path == "/dist/browser.php":
            if query.get("action", [""])[0] == "logout":
                self.note("LOGOUT LINK FOLLOWED")
                SESSIONS.clear()
                return self.send_page(signin_page())
            if self.has_details(form):
                session = secrets.token_hex(16)
                SESSIONS.add(session)
                SESSION_AGENT[session] = self.headers.get("User-Agent") or ""
                self.note("signed in with details")
                return self.send_page(real_listing(session), session, "PHPSESSID")
            if posted:
                self.note("refused")
                return self.send_page(denied_page())
            self.note("no details: bounced to the sign-in page")
            return self.bounce()

        if path in ("/dist/", "/dist/index.html"):
            self.note("sign-in page")
            return self.send_page(signin_page())

        if path == "/dist/browser.php":
            if query.get("action", [""])[0] == "logout":
                self.note("LOGOUT LINK FOLLOWED")
                SESSIONS.clear()
                return self.send_page(signin_page())
            if self.has_details(form):
                cookie = None
                if ARGS.session == "cookie":
                    cookie = secrets.token_hex(16)
                    SESSIONS.add(cookie)
                self.note("signed in with details")
                return self.send_page(listing(query), cookie)
            if posted:
                self.note("refused")
                return self.send_page(denied_page())
            if self.has_cookie():
                self.note("listing by cookie")
                return self.send_page(listing(query))
            self.note("no sign-in: sign-in page")
            return self.send_page(signin_page())

        if path == "/dist/download.php":
            name = (query.get("file") or form.get("file") or [""])[0]
            known = name in [n for _, n in FILES]
            if not (self.has_cookie() or self.has_details(form)):
                self.note("download refused")
                return self.send_page(denied_page())
            if not known:
                self.note("download of unknown file")
                return self.send_page(page("Software Distribution", "<h1>File not found</h1>"))
            return self.send_file(name)

        self.note("not found")
        body = page("Not found", "<h1>Not found</h1>")
        self.send_response(404)
        self.send_header("Content-Type", "text/html; charset=UTF-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return None

    def do_GET(self):
        self.handle_any({})

    def do_POST(self):
        self.handle_any(self.form())


def main():
    global ARGS
    parser = argparse.ArgumentParser(description="Stand-in for PixInsight's download service (this computer only).")
    parser.add_argument("--port", type=int, default=8719)
    parser.add_argument("--layout", choices=["links", "folders", "forms", "real"], default="links")
    parser.add_argument("--cdn", choices=["none", "same", "other"], default="none")
    parser.add_argument("--refuse-curl", action="store_true")
    parser.add_argument("--strict-agent", action="store_true")
    parser.add_argument("--only-old", action="store_true")
    parser.add_argument("--newest", default="",
                        help="also list installers of this made-up version, so that there is something "
                             "newer than whatever PixInsight is installed on this computer")
    parser.add_argument("--only-version", default="",
                        help="list installers of this one version and nothing else")
    parser.add_argument("--bad-sha1", action="store_true")
    parser.add_argument("--slow-ms", type=int, default=0)
    parser.add_argument("--drop-first-mb", type=int, default=0)
    parser.add_argument("--session", choices=["cookie", "none"], default="cookie")
    parser.add_argument("--size-mb", type=int, default=8)
    parser.add_argument("--log", default="")
    ARGS = parser.parse_args()
    if ARGS.newest:
        REAL_FILES[:0] = ["PI-windows-x64-gpu-%s-20991231-c.exe" % ARGS.newest,
                          "PI-macosx-x64-%s-20991231-c.pkg" % ARGS.newest,
                          "PI-macosx-arm64-%s-20991231-c.pkg" % ARGS.newest,
                          "PI-linux-x64-gpu-%s-20991231-c.tar.xz" % ARGS.newest]
    if ARGS.only_version:
        REAL_FILES[:] = ["PI-windows-x64-%s-20200101-c.exe" % ARGS.only_version,
                         "PI-macosx-x64-%s-20200101-c.pkg" % ARGS.only_version,
                         "PI-macosx-arm64-%s-20200101-c.pkg" % ARGS.only_version,
                         "PI-linux-x64-%s-20200101-c.tar.xz" % ARGS.only_version]
    for start in (b"xar!", b"MZ"):
        FILE_SHA1[start] = hashlib.sha1(start + b"\0" * (ARGS.size_mb * 1048576 - len(start))).hexdigest()
    # 127.0.0.1 only: nothing outside this computer can reach the stand-in.
    server = ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler)
    print("stand-in download service on http://127.0.0.1:%d/dist/ (layout=%s, session=%s, cdn=%s)"
          % (ARGS.port, ARGS.layout, ARGS.session, ARGS.cdn), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
