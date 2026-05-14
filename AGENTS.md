# WebDriverAgent Agent Guide

Use this repository guide for shared, workspace-level behavior. Keep it minimal and link to existing docs instead of copying them.

## Start Here

- Read [README.md](README.md) for setup and bundle workflows.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing style, tests, or docs.

## Repository Shape

- `lib/`: TypeScript package consumed by Appium. It launches WDA, manages `xcodebuild`, and exposes session and no-session proxies.
- `WebDriverAgentLib/`: Objective-C server and XCTest integration. Route registration, request handling, element lookup, and native interactions live here.
- `WebDriverAgentRunner/`: XCTest runner target used to launch WDA on device/simulator.
- `WebDriverAgentTests/`: Objective-C integration and unit tests for native behavior.
- `test/`: Node-based unit and functional tests for the TypeScript wrapper.
- `Scripts/`: build, bundle, and version-sync scripts.

## Common Commands

- `npm run build`: compile the TypeScript wrapper.
- `npm run lint`: run ESLint for the TypeScript code.
- `npm test`: run TypeScript unit tests under `test/unit`.
- `npm run e2e-test`: run TypeScript functional tests under `test/functional`.
- `npm run bundle`: build simulator bundles for iOS and tvOS.
- Native workflow: open `WebDriverAgent.xcodeproj` and run the `WebDriverAgentRunner` test target when validating `WebDriverAgentLib` changes.

## Conventions That Matter

- Treat TypeScript and Objective-C as separate layers. If behavior changes at the HTTP endpoint or XCTest level, inspect `WebDriverAgentLib` first; if it changes launch/proxy/build behavior, inspect `lib/` first.
- Keep Objective-C edits small and local. Route definitions live in each command class `+routes` method.
- Follow the repository Objective-C style from [CONTRIBUTING.md](CONTRIBUTING.md): 2-space indentation and short lines where practical.
- Follow the existing TypeScript formatting from [package.json](package.json): single quotes, 100-column Prettier width, and no unnecessary API reshaping.

## No-Session Route Rules

- Adding `.withoutSession` to a route means `request.session` may be `nil`. Do not leave any unconditional use of `request.session.elementCache`, `request.session.activeApplication`, or other session-owned objects in the handler.
- UUID-based element lookup through `FBElementCache` is session-backed. If a route must work without a session, either provide a fallback that does not require the cache or do not mark the route `.withoutSession`.
- `XCUIApplication.fb_activeApplication` is the standard fallback when a handler only needs the active app and can work without session state.
- `FBTypeText` in `XCUIElement+FBTyping` sends synthesized keyboard input to the currently focused element and is the preferred primitive when direct text entry must avoid session-owned app state.
- For click/tap work, prefer existing coordinate or synthesized-event helpers when the interaction does not need session-backed element resolution.

## High-Value Files

- [lib/webdriveragent.ts](lib/webdriveragent.ts): WDA startup, proxy setup, and no-session proxy wiring.
- [lib/xcodebuild.ts](lib/xcodebuild.ts): build/test launch flow and Xcode command construction.
- [WebDriverAgentLib/Commands/FBElementCommands.m](WebDriverAgentLib/Commands/FBElementCommands.m): element routes, click/input handlers, and several examples of session fallback.
- [WebDriverAgentLib/Categories/XCUIApplication+FBHelpers.h](WebDriverAgentLib/Categories/XCUIApplication+FBHelpers.h): active-application helpers.
- [WebDriverAgentLib/Categories/XCUIElement+FBTyping.h](WebDriverAgentLib/Categories/XCUIElement+FBTyping.h): direct text typing primitives.
- [WebDriverAgentTests/IntegrationTests/FBTypingTest.m](WebDriverAgentTests/IntegrationTests/FBTypingTest.m): native typing behavior examples.

## Validation Expectations

- After TypeScript changes, run the narrowest relevant check from `npm run build`, `npm run lint`, `npm test`, or `npm run e2e-test`.
- After Objective-C route or XCTest changes, prefer a native validation path in Xcode or the closest existing native test before widening scope.