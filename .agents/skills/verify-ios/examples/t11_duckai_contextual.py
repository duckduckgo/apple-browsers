"""On a web page, Duck.ai opens over it with the page attached, answers a prompt in the sheet, Fire from the sheet
deletes the chat and keeps the page, and a new chat expands to its own Duck.ai tab."""
from verify_ios import steps

LIVE = ["duck.ai"]
FLAGS = {**steps.CONTEXTUAL_FLAGS}   # a copy: overrides stay in this proof


def run(ios):
    steps.fresh_start(ios)
    token = ios.token("t11")
    steps.open_fixture(ios, token)

    steps.open_contextual_chat(ios)   # entry button → Ask About Page
    ios.check("the fixture page is attached", steps.attached_context(ios) == "verify-ios fixture",
              steps.attached_context(ios))
    ios.shot("attached")
    steps.send_contextual_prompt(ios, "reply with exactly the word pineapple")
    answer = steps.read_contextual_answer(ios)
    ios.check("the sheet shows an answer containing pineapple", "pineapple" in answer.lower(), answer)
    ios.shot("answer")
    ios.unverified("the page content reached the model",
                   "the local fixture's content is not delivered to Duck.ai (see features/duck-ai-contextual.md)")

    steps.fire_contextual_chat(ios)
    ios.expect_url_contains(token)   # Fire from the sheet leaves the page's tab alone
    ios.tap(steps.ids(ios)["aichat"])
    ios.wait('label="Ask About Page"', "exists", 5)   # no chat to reopen: the entry offers its menu again
    ios.shot("chat-deleted")

    ios.tap('label="Ask About Page"')
    ios.wait("id=AIChat.ContextChip.AttachedTitle", "exists", 15)
    steps.send_contextual_prompt(ios, "reply with exactly the word mango")
    ios.check("the second chat answered", "mango" in steps.read_contextual_answer(ios).lower())
    steps.expand_contextual_chat(ios)
    ios.expect_hidden("id=AIChat.ContextualSheet")
    ios.check("the chat moved to a Duck.ai tab", "duck.ai" in ios.url())
    ios.shot("final")
