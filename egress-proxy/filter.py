"""mitmproxy addon — egress control for the hardened agent.

Two modes, selected by the DEFENSE environment variable:

  DEFENSE=off  (NAIVE allowlist = destination filter)
      Only checks that the destination host is on the allowlist. Any request to
      an allowed host passes, including an attacker abusing the trusted API with
      an injected token to upload the workspace/secret. -> exfil SUCCEEDS.
      This reproduces the Anthropic Cowork incident: "we conceptualised the
      allowlist as a destination filter when it is a capability grant."

  DEFENSE=on   (DEFENSIVE MITM = capability-aware inspection)
      Same allowlist, PLUS content/identity inspection on the trusted API:
        1. validates the session token (rejects attacker-injected tokens),
        2. blocks upload-style calls / requests carrying secret-looking data,
        3. logs every request for audit.
      Legitimate model calls still pass. -> exfil BLOCKED.

Kept on plain HTTP in the lab to inspect content without CA-install friction;
the production analogue is TLS-terminating MITM (srt `tlsTerminate`).
"""
import os
import re
from mitmproxy import http

ALLOWLIST = {"api.trusted.local", "litellm"}
DEFENSE = os.environ.get("DEFENSE", "off").lower() == "on"
# The one legitimate, proxy-minted session token. An attacker who injects their
# own key into a workspace file cannot know this value.
LEGIT_SESSION_TOKEN = os.environ.get("LEGIT_SESSION_TOKEN", "legit-session-abc123")

SECRET_RE = re.compile(r"(sk-ant-|FAKE_API_KEY|BEGIN [A-Z ]*PRIVATE KEY)")


def _audit(flow, verdict, reason):
    print(f"[egress][{'DEFENSE' if DEFENSE else 'NAIVE'}] {verdict} "
          f"{flow.request.method} {flow.request.pretty_host}{flow.request.path} "
          f"-> {reason}", flush=True)


def request(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host

    # Layer 1: destination allowlist (a capability grant). Applies in both modes.
    if host not in ALLOWLIST:
        _audit(flow, "BLOCK", f"host {host!r} not in allowlist")
        flow.response = http.Response.make(403, b"egress denied: host not allowed\n")
        return

    if not DEFENSE:
        # NAIVE: destination allowed -> let everything through.
        _audit(flow, "ALLOW", "naive destination allowlist")
        return

    # Layer 2 (DEFENSE only): identity + content inspection on the trusted API.
    token = flow.request.headers.get("X-Session-Token", "")
    if token != LEGIT_SESSION_TOKEN:
        _audit(flow, "BLOCK", "invalid/attacker session token")
        flow.response = http.Response.make(403, b"egress denied: bad session token\n")
        return

    if flow.request.path.startswith("/v1/upload"):
        _audit(flow, "BLOCK", "upload endpoint disabled by policy")
        flow.response = http.Response.make(403, b"egress denied: upload not permitted\n")
        return

    body = flow.request.get_text(strict=False) or ""
    if SECRET_RE.search(body):
        _audit(flow, "BLOCK", "request body carries secret material")
        flow.response = http.Response.make(403, b"egress denied: secret in payload\n")
        return

    _audit(flow, "ALLOW", "valid session, no secret, non-upload")
