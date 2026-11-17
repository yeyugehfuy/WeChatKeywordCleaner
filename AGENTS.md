# Repository working rules

## Supported runtime

- The supported target is WeChat 8.0.68 on iOS 14–16.6, arm64/rootless TrollStore or TrollFools injection.
- WeChat private APIs are version-coupled. Do not claim a selector or field exists unless it is confirmed for this exact build or guarded with `respondsToSelector:`.
- Keep search backends as fallbacks until device evidence identifies a dead path. Record which candidate route ran, candidate counts, exact-match counts, and the failure reason in the UI diagnostic and log.

## Search and deletion safety

- FTS results are candidates only. Require a fresh `GetMsg:LocalID:` lookup for every selected local ID immediately before deletion, check the returned wrapper type and local ID, and verify the original message text contains the literal keyword.
- Validate the entire selection before sending any delete request. Group requests by talker and always pass `DelAll:NO`.
- Delete only explicitly selected messages after a confirmation that states the count and affected chats. Never call conversation-wide deletion APIs.
- Treat missing read-back APIs, exceptions, unexpected return types, and remaining rows as “not confirmed”; never report success when deletion cannot be verified.
- A partially completed multi-chat deletion must be described as potentially partial so the user can re-search before retrying.

## Build and device verification

- A GitHub Actions compile/package pass proves only that the tweak builds. It does not prove search works, deletion works, or the runtime selectors match the installed WeChat.
- Report the exact commit and artifact for every user test. Record device WeChat/iOS versions, the native WeChat search result, cleaner candidate count, selected count, and post-delete re-search result.
- Do not remove a search fallback or change private API signatures based only on a successful build. Require a reproducible device log or source evidence for the target version.
- Preserve the stable Settings entry unless the user asks to change its placement.

## Change hygiene

- Keep one coherent commit per fix. Update `scripts/check_contracts.py` when changing any guarded safety contract.
- Run the source contract check locally when available; GitHub Actions must run it before compilation.
- Keep the root retrospective current when repeated bugs reveal a new shared cause. Remove code only after confirming it has no runtime or compatibility role.
