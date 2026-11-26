"""Deleting a Duck.ai chat with the Fire button's "Delete This Chat" removes it from chat history and from Duck.ai's
storage, and leaves the user's other chat in both."""
from verify_ios import steps

LIVE = ["duck.ai"]
FLAGS = {"aiChatNativeStorage": True, "aiChatNativeDataAccess": True,   # where production keeps chats
         "fireButtonRefinements": True, "fireMode": True}                # the "Delete This Chat" sheet


def start_chat(ios, word, tag):
    steps.send_duckai_prompt(ios, f"reply with exactly the word {word} (ignore this tag: {tag})")
    answer = steps.read_duckai_answer(ios)
    ios.check(f"answer contains {word}", word in answer.lower(), answer)
    return steps.duckai_chat_id(ios)


def run(ios):
    steps.fresh_start(ios)
    keep_tag, gone_tag = ios.token("keep"), ios.token("gone")
    steps.open_duckai_new_chat(ios)
    keep = start_chat(ios, "mango", keep_tag)
    steps.new_duckai_chat_tab(ios)
    gone = start_chat(ios, "kiwi", gone_tag)
    ios.note(f"{ios.device}: kept chat {keep}, deleted chat {gone}; entry point {steps.ids(ios)['aichat']}")

    # Titles are generated after the answer; read them from storage so history can be matched to chat ids.
    titles = ios.eventually("both chats stored with titles", lambda: (lambda c: c.get(keep) and c.get(gone) and c)(
        {c["id"]: c["title"] for c in steps.duckai_storage(ios, [])["chats"]}), 30)
    ios.check("the two chats have different titles", titles[keep] != titles[gone], titles)
    before = steps.duckai_history(ios)
    ios.check("history lists both chats before", titles[keep] in before and titles[gone] in before, before)
    stored = steps.duckai_storage(ios, [gone, gone_tag])
    ios.check("storage holds the chat before", "native:chats" in stored["hits"], stored)
    ios.shot("before")

    ios.mark()
    steps.delete_current_duckai_chat(ios)
    ios.expect_wide_event("data-clearing", status="SUCCESS")

    after = ios.eventually("history drops the deleted chat",
                           lambda: (lambda h: titles[gone] not in h and h)(steps.duckai_history(ios)), 20)
    ios.check("history still lists the other chat", titles[keep] in after, after)
    stored = ios.eventually("storage drops the deleted chat",
                            lambda: (lambda s: not s["hits"] and s)(steps.duckai_storage(ios, [gone, gone_tag])), 20)
    ios.check("the other chat is still stored", keep in [c["id"] for c in stored["chats"]], stored)
    ios.note(f"by design, native storage keeps the deleted id as a sync tombstone: {stored['tombstones']}")
    ios.shot("after")
