"""Cognito pre-token-generation (V2_0) trigger for the Claude apps gateway.

The gateway matches its configured admin group against a top-level ``groups``
claim, but Cognito's native claim is ``cognito:groups`` and SAML-federated group
membership arrives in the mapped ``custom:groups`` attribute. This trigger
gathers both sources and emits a ``groups`` claim.

CUSTOMIZATION POINT -- claim format:
Cognito ``claimsToAddOrOverride`` values are strings, so ``groups`` is emitted
here as a space-delimited string. If your gateway expects ``groups`` as a JSON
array, change ``_emit`` below to ``json.dumps(group_list)`` and confirm the
gateway parses it. ``cognito:groups`` is also set (a real array) via
``groupOverrideDetails`` in case you point the gateway there instead.
"""

import json


def _collect_groups(event):
    groups = set()

    grp_cfg = (event.get("request", {}) or {}).get("groupConfiguration") or {}
    for g in grp_cfg.get("groupsToOverride") or []:
        if g:
            groups.add(g)

    attrs = (event.get("request", {}) or {}).get("userAttributes") or {}
    raw = attrs.get("custom:groups") or attrs.get("groups") or ""
    for g in raw.replace(";", ",").split(","):
        g = g.strip()
        if g:
            groups.add(g)

    return sorted(groups)


def handler(event, context):
    group_list = _collect_groups(event)
    _emit = " ".join(group_list)  # see CUSTOMIZATION POINT in the module docstring

    event.setdefault("response", {})
    event["response"]["claimsAndScopeOverrideDetails"] = {
        "idTokenGeneration": {
            "claimsToAddOrOverride": {"groups": _emit},
        },
        "groupOverrideDetails": {
            "groupsToOverride": group_list,
        },
    }
    return event
