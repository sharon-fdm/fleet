# Fleet iOS Agent — Demo Video Script

## Scene 1: Introduction (Fleet dashboard)
**[Fleet dashboard hosts page on screen]**

> "Today I'm going to show you something new — a native iOS agent for Fleet that brings osquery-like capabilities to iPhones and iPads."

> "Right now Fleet manages iOS devices through MDM only — we can push profiles and collect basic device info. But we can't run queries, check policies, or get real-time data from the device. This is a proof of concept for what an iOS agent could look like."

## Scene 2: The App (iPhone simulator)
**[Switch to iPhone simulator showing the app — fresh install, not enrolled]**

> "Here's the Fleet Agent app running on an iPhone 16 simulator. It's a native Swift app — no third-party dependencies, built specifically for iOS."

> "Let me configure it to connect to our Fleet server."

**[Tap gear → Server Config → enter server URL and enroll secret → Save]**

> "Now let's enroll this device."

**[Tap Enroll button]**

> "The app just enrolled with Fleet using the same orbit enrollment protocol that our desktop agents use. You can see the node key — the device is now managed."

## Scene 3: Polling & Vitals
**[Wait for a couple poll cycles, show Poll #2-3]**

> "The agent is now polling Fleet every 15 seconds. It fetches configuration, executes detail queries, and reports device information back — just like osquery does on macOS."

**[Switch to Fleet UI → Host detail page for iPhone 16]**

> "And here in Fleet, the iPhone shows up as a fully populated host. We can see iOS 26, Apple ARM64, 14 cores, the hostname — all collected automatically by the agent."

## Scene 4: Live Queries
**[Fleet UI → Queries → Add query]**

> "Now the fun part — live queries. Let me query this iPhone in real time."

**[Type: SELECT * FROM os_version → Run → Select the iPhone → Run]**

> "We're running a SQL query against the iPhone, and the results come back in seconds. iOS 26.4.1, platform iOS."

**[New query: SELECT * FROM disk_space → Run]**

> "Let's check disk space."

**[New query: SELECT * FROM accessibility_settings → Run]**

> "And accessibility settings — bold text, reduce motion, VoiceOver status. These are all native iOS APIs exposed as queryable tables."

## Scene 5: Tables
**[iPhone simulator → gear menu → Query Tables]**

> "The agent has 16 virtual tables covering device info, OS version, battery, disk space, network, system info, screen, locale, thermal state, accessibility, uptime, and more."

## Scene 6: Policies
**[Fleet UI → Policies page]**

> "We also support policies. These are compliance checks that run automatically on every poll cycle."

**[Show policy results — some passing, some failing]**

> "The iPhone is passing 'Device is iOS' and 'Wi-Fi connected', but failing 'Biometrics available' because this is a simulator with no Face ID. On a real device, that would pass."

**[Fleet UI → Host detail → Policies tab]**

> "And here on the host page, we can see the policy compliance status for this specific device."

## Scene 7: My Device
**[iPhone simulator → gear → My Device]**

> "The app also has a 'My Device' view — similar to Fleet Desktop on macOS. It shows the device owner their compliance status, device details, and agent health."

## Scene 8: Architecture
**[Back to Fleet dashboard]**

> "Under the hood, this is a full agent — not just MDM. It enrolls via the orbit protocol, polls for configuration and distributed queries, executes them locally through a table-dispatch engine, and submits results back to Fleet."

> "It supports background execution via iOS BGAppRefreshTask, and can be woken instantly by silent push notifications through APNs — the same infrastructure Fleet already uses for MDM."

## Scene 9: Wrap Up

> "This is about 4,000 lines of Swift on the client side and 150 lines of Go server changes. 16 queryable tables, 68 unit tests, live queries, policies, scheduled queries, and detail queries — all working end to end."

> "Thanks for watching."
