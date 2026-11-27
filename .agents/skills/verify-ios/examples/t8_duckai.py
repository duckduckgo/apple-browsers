"""Duck.ai opens from its in-app entry point, takes a prompt, and streams back an answer."""
from verify_ios import steps

LIVE = ["duck.ai"]


def run(ios):
    steps.fresh_start(ios)   # a run must not start on a previous run's Duck.ai tab
    steps.open_duckai_new_chat(ios)
    steps.send_duckai_prompt(ios, "reply with exactly the word pineapple")
    answer = steps.read_duckai_answer(ios)
    ios.check("answer contains pineapple", "pineapple" in answer.lower(), answer)
    ios.shot("final")
