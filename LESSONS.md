# Lessons learned

Problems that took real troubleshooting, and what fixed them.

## Browser desktops dropped keystrokes (WebSockets through IIS ARR)
Guacamole's browser desktops showed the screen but ignored typing. Browsers offer `permessage-deflate` compression
on WebSocket upgrades; IIS Application Request Routing can't proxy a compressed WebSocket and answered 502.5, so
Guacamole silently fell back to its HTTP tunnel, where keyboard POSTs failed behind the sign-in proxy.
**Fix:** blank the `Sec-WebSocket-Extensions` request header in the rewrite rule so the upgrade is negotiated
uncompressed.

## HTTP/2 breaks the same WebSockets
With HTTP/2 enabled on the 443 binding, browsers never attempt the HTTP/1.1 upgrade WebSockets need through ARR.
**Fix:** disable HTTP/2 on the HTTP.sys binding, and re-apply that flag automatically whenever a certificate renewal
re-creates the binding (the monitor checks for drift every five minutes).

## An outbound rewrite rule that stalled every stream
A response rewrite rule (fixing redirect `Location` headers for one app) made IIS buffer *every* response on the
site, which froze long-lived desktop streams. **Fix:** scope outbound rules with a precondition so they only apply
to the one host and content type they are meant for.

## Idle desktops disconnected after 30 seconds
The sign-in proxy's default upstream timeout closed quiet WebSocket connections. **Fix:** a long upstream timeout
on the proxy for the desktop route.

## Header-based single sign-on must be tamper-proof
Apps behind the gateway trust identity headers. Every public rewrite rule blanks those headers on the way in, so a
visitor can never supply their own; only the gateway sets them.

## Remote Desktop certificate warnings on the LAN
Inside the house the desktop names resolve straight to the VMs, which presented self-signed certificates. **Fix:**
a separate DNS-01 certificate for the desktop names, pushed to each Windows RDP listener and each Linux xrdp service
by a deploy script that win-acme runs after every renewal.

## Signing out that didn't sign out
Sign-out worked, but the portal page had no cache headers, so the browser redisplayed its cached copy.
**Fix:** `Cache-Control: no-cache` on the portal's static pages.

## Overlapping sign-ins gave a 500
Two sign-in attempts in one browser (a second tab, a background refresh) overwrote each other's PKCE verifier
cookie. **Fix:** per-request CSRF cookies on the proxy, and API calls answer 401 instead of starting a new sign-in.

## The real client IP was invisible
The Flask app's WSGI server strips untrusted proxy headers by default, so every visitor looked like 127.0.0.1.
**Fix:** keep `X-Forwarded-For` (the app only listens on loopback behind IIS) and take the right-most address
that isn't the server's own, so a visitor can't spoof it by prepending entries.
