"""The web channel: the app's own AutomationServer (SharedPackages/AutomationServer), on [::1]:<port> with a bearer token.

Request format mirrors macOS/scripts/crossbench/ddg-automation.py. It belongs to the app, not to the UI driver, so it
stays the same whatever drives the native UI.
"""
import base64, json, time, urllib.error, urllib.parse, urllib.request

from .env import Failed


class Web:
    def __init__(self, port, token):
        self.port = port
        self.token = token

    def req(self, path, params=None, method="GET", timeout=30):
        q = urllib.parse.urlencode(params or {}, quote_via=urllib.parse.quote)
        r = urllib.request.Request(f"http://[::1]:{self.port}{path}" + (f"?{q}" if q else ""),
                                   data=(b"" if method == "POST" else None), method=method)
        r.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(r, timeout=timeout) as resp:
                return json.load(resp).get("message")
        except urllib.error.HTTPError as e:
            # AutomationServer answers errors as HTTP 400 with the reason in the body (e.g. noWindow, invalidURL)
            raise urllib.error.HTTPError(e.url, e.code, f"{e.reason}: {e.read().decode(errors='replace')[:300]}", e.headers, None)

    def ready_now(self):
        try:
            return self.req("/contentBlockerReady", timeout=2) == "true"
        except Exception:
            return False

    def wait_ready(self, timeout=60):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.ready_now():
                return int((time.time() - t0) * 1000)
            time.sleep(0.25)
        return None

    def page_url(self):
        """The current tab's URL, or None when the tab shows no web page (the new-tab page, Duck.ai native UI)."""
        return self.req("/getUrl") or None

    def url(self):
        """The current tab's URL; fails when the tab has no web page, so "token not in url()" can't pass vacuously."""
        u = self.page_url()
        if u is None:
            raise Failed("the current tab shows no web page (no URL); use page_url() to test for that")
        return u

    def navigate(self, url):
        try:
            return self.req("/navigate", {"url": url})
        except urllib.error.HTTPError as e:
            if "AutomationServerError error 0" in str(e.reason):   # case 0 is noWindow
                raise Failed("web navigate needs a tab showing a web page; the new-tab page has none. "
                             "Load a page through the address bar first")
            raise

    def eval(self, js):
        """Run JS in the page and return its result. The script must return a value: AutomationServer rejects null."""
        raw = self.req("/execute", {"script": js, "args": "{}"}, method="POST")
        return json.loads(raw) if raw else None

    def handles(self):
        return json.loads(self.req("/getWindowHandles"))

    def screenshot(self, path):
        m = self.req("/screenshot", timeout=60)
        try:
            m = json.loads(m)
        except (TypeError, ValueError):
            pass
        b64 = m.get("value") if isinstance(m, dict) else m
        with open(path, "wb") as f:
            f.write(base64.b64decode(b64))
        return path

    def find(self, kind, value):
        """Read-only lookup for web:css= / web:text= locators; returns {text, tag, visible, enabled} or None.
        `visible`: rendered with a size, not display:none / visibility:hidden / opacity 0, and intersecting the viewport."""
        pick = (f"var e=document.querySelector({json.dumps(value)});" if kind == "css" else
                f"var t={json.dumps(value)}; var e=[...document.querySelectorAll('body *')]"
                ".find(x=>x.children.length==0&&x.innerText&&x.innerText.trim()==t);")
        js = pick + (" if(!e) return {found:false};"
                     " var s=getComputedStyle(e), r=e.getBoundingClientRect();"
                     " var vis=r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'&&parseFloat(s.opacity)>0"
                     "&&r.bottom>0&&r.right>0&&r.top<innerHeight&&r.left<innerWidth;"
                     " return {found:true,text:e.innerText||e.value||'',tag:e.tagName,visible:vis,enabled:!e.disabled&&!e.closest('[disabled]')}")
        r = self.eval(js)
        if isinstance(r, dict) and "error" in r:
            raise RuntimeError("web eval: " + r["error"])
        return r if isinstance(r, dict) and r.get("found") else None


SUMMARY_JS = """var q=s=>[...document.querySelectorAll(s)];
return JSON.stringify({url:location.href,title:document.title,
 headings:q('h1,h2,h3').map(e=>e.innerText).slice(0,20),
 links:q('a').map(e=>({text:e.innerText,href:e.getAttribute('href'),label:e.getAttribute('aria-label')})).slice(0,30),
 buttons:q('button').map(e=>({text:e.innerText,disabled:e.disabled,id:e.id})).slice(0,30),
 inputs:q('input,textarea').map(e=>({id:e.id,value:e.value,placeholder:e.placeholder})).slice(0,20),
 text:document.body.innerText.slice(0,1500)})"""
