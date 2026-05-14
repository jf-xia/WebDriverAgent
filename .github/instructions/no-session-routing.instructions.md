---
description: "Use when editing WebDriverAgentLib route definitions, FBElementCommands, no-session command handlers, or typing/click behavior that may bypass request.session."
applyTo: "WebDriverAgentLib/{Commands,Categories,Routing}/**/*.{h,m}"
---

# No-Session Routing

- Treat `.withoutSession` as a control-flow change, not just a route flag. The paired handler must survive `request.session == nil`.
- Before adding `.withoutSession`, check every use of `request.session`, `request.session.elementCache`, and `request.session.activeApplication` in the full handler path.
- Session-backed UUID lookup through `FBElementCache` is not safe once the request can arrive without a session. Replace it only when there is a concrete fallback.
- If the handler only needs the frontmost app, prefer `XCUIApplication.fb_activeApplication` over `request.session.activeApplication`.
- For direct text entry, prefer `FBTypeText(...)` when the focused element path is sufficient. `fb_typeText:` still taps the element first when needed, so it usually still depends on resolving an element instance.
- For click/tap behavior, consider coordinate or synthesized-event helpers when the route no longer has a safe way to resolve an element from the session cache.
- Keep route edits and handler edits in the same change. A `.withoutSession` route without a handler fallback is incomplete.
- When the no-session path changes typing or tap behavior, look for the nearest native test under `WebDriverAgentTests/IntegrationTests` before adding broader coverage.

Relevant code anchors:

- [WebDriverAgentLib/Commands/FBElementCommands.m](WebDriverAgentLib/Commands/FBElementCommands.m)
- [WebDriverAgentLib/Categories/XCUIApplication+FBHelpers.h](WebDriverAgentLib/Categories/XCUIApplication+FBHelpers.h)
- [WebDriverAgentLib/Categories/XCUIElement+FBTyping.h](WebDriverAgentLib/Categories/XCUIElement+FBTyping.h)
- [WebDriverAgentTests/IntegrationTests/FBTypingTest.m](WebDriverAgentTests/IntegrationTests/FBTypingTest.m)