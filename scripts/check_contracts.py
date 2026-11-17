#!/usr/bin/env python3
"""Small source-level safety contracts for the private-API tweak."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

bridge = (ROOT / "WeChatBridge.m").read_text(encoding="utf-8")
ui = (ROOT / "KeywordCleanerUI.m").read_text(encoding="utf-8")
control_text = (ROOT / "control").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")

# Candidates must be validated against exact, literal message text.
check(bridge.count("rangeOfString:keyword") >= 2, "search and pre-delete literal verification must remain")
check(bridge.count("NSLiteralSearch") >= 2, "both search and pre-delete checks must use literal matching")
check("__msgWrap" not in bridge, "do not retain unused message wrappers in result dictionaries")

# Refetch and validate every selected message before submitting any delete batch.
delete_start = bridge.find("+ (void)deleteMessages:")
delete_end = bridge.find("// DelMsg is void", delete_start)
delete_body = bridge[delete_start:delete_end] if delete_start >= 0 and delete_end > delete_start else ""
refetch = delete_body.find('KWSendMessageForLocalID(messageManager, getMessageSelector, talker, localID)')
literal_check = delete_body.find("rangeOfString:keyword")
delete_call = delete_body.find("KWSendDeleteBatch(messageManager, deleteSelector, talker")
check(delete_start >= 0 and delete_end > delete_start, "delete flow and read-back boundary must remain recognizable")
check(refetch >= 0 and literal_check > refetch and delete_call > literal_check,
      "fresh lookup and literal keyword validation must precede every batch delete")
check('((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(target, selector, talker, wraps, NO)' in bridge,
      "batch deletion must keep DelAll:NO")

readback_start = bridge.find('SEL getMessagesSelector = NSSelectorFromString("GetMsg:LocalIDArray:")')
readback_end = bridge.find("});", readback_start)
readback = bridge[readback_start:readback_end] if readback_start >= 0 and readback_end > readback_start else ""
check("if (![messageManager respondsToSelector:getMessagesSelector])" in readback and
      "completion(NO)" in readback and "return;" in readback,
      "missing read-back API must fail closed")
check("completion(verified ? allRemoved : YES)" not in bridge,
      "unverified deletion must never be reported as success")

# Keep user-visible selection and confirmation controls.
check('@"全选"' in ui and '@"取消全选"' in ui, "select-all and deselect-all controls must remain")
check('@"确认删除当前选中消息？"' in ui and '@"取消"' in ui and '@"确认删除"' in ui,
      "deletion must remain behind explicit confirmation")

check("需自行补" not in control_text, "package description must not claim bridge implementation is unfinished")
check(bool(re.search(r"(?m)^Version: \d+\.\d+\.\d+$", control_text)), "package version must be semantic")

check("branches: [main]" in workflow and "branches: [main, master]" not in workflow,
      "push trigger must target the existing main branch")
check("python3 scripts/check_contracts.py" in workflow,
      "Actions must run source contracts before compilation")

if errors:
    for error in errors:
        print(f"FAIL: {error}")
    sys.exit(1)
print("PASS: source safety contracts")
