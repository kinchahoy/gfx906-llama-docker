#!/usr/bin/env -S uv --quiet run --script
# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "httpx",
# ]
# ///
import os, json, re, httpx

BASE  = os.getenv("BASE", "http://192.168.0.83:8000")
MODEL = os.getenv("MODEL", "oss-120b-100k-ultra")
c = httpx.Client(timeout=60)

def req(n: int):
    r = c.post(f"{BASE}/v1/chat/completions",
               json={"model": MODEL, "messages":[{"role":"user","content":"A "*n}], "max_tokens": 1})
    if r.status_code == 404:
        r = c.post(f"{BASE}/v1/completions",
                   json={"model": MODEL, "prompt":"A "*n, "max_tokens": 1})
    if r.status_code == 200:
        j = r.json()
        return True, j.get("usage", {}).get("prompt_tokens")
    m = re.search(r"(maximum context length|max[_ -]?model[_ -]?len|ctx|context)\D{0,40}(\d{3,})", r.text, re.I)
    return False, int(m.group(2)) if m else r.text[:400]

def bs(lo: int, hi: int, last):
    while lo + 1 < hi:
        mid = (lo + hi) // 2
        ok, v = req(mid)
        if ok: lo, last = mid, (v or last)
        else:  hi = mid
    return {"model": MODEL, "max_prompt_tokens": last, "approx_words_unitA": lo}

def probe():
    lo, hi, last = 0, 2048, None
    while True:
        ok, v = req(hi)
        if ok:
            lo, last, hi = hi, (v or last), hi * 2
            if hi > 1_000_000:
                return {"model": MODEL, "max_prompt_tokens": last, "approx_words_unitA": lo, "note": "hit safety cap"}
        else:
            return {"model": MODEL, "reported_limit": v} if isinstance(v, int) else bs(lo, hi, last)

print(json.dumps(probe()))
