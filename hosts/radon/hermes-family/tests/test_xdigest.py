import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone

from hermes_family import xdigest
from tests.support import temp_dir

NOW = datetime(2026, 11, 1, 8, 0, tzinfo=timezone.utc)


def entry(n: int, *, seen: str = "2026-10-30T12:00:00Z", via: str = "poll", **post) -> dict:
    """An archive line as x-bookmarks writes it. Made up, like every value in these tests."""
    return {
        "id": str(1900000000000000000 + n),
        "first_seen_at": seen,
        "via": via,
        "post": {"id": str(1900000000000000000 + n), "text": f"post {n}", "author_id": "3000",
                 "created_at": "2026-10-29T07:00:00.000Z", **post},
        "includes": {"users": [{"id": "3000", "username": "user_a", "name": "User A"}]},
    }


def passes(blocks: list[str]) -> list[str]:
    return ["" for _ in blocks]


class DigestTest(unittest.TestCase):
    def test_without_new_bookmarks_this_week_no_agent_runs(self):
        entries = [
            entry(1, via="backfill"),
            entry(2, via="import"),
            entry(3, seen="2026-10-24T12:00:00Z"),
        ]
        self.assertEqual(xdigest.render(entries, NOW, passes), '{"wakeAgent": false}')

    def test_a_bookmark_becomes_a_block_with_its_full_text_quote_and_outside_links(self):
        bookmarked = entry(
            1,
            text="cut short…",
            note_tweet={"text": "the whole long post"},
            referenced_tweets=[{"type": "quoted", "id": "42"}, {"type": "replied_to", "id": "43"}],
            entities={"urls": [
                {"expanded_url": "https://x.com/user_a/status/1900000000000000001/photo/1"},
                {"expanded_url": "https://example.org/paper"},
                {"expanded_url": "https://example.org/paper"},
            ]},
        )
        bookmarked["includes"]["tweets"] = [
            {"id": "42", "text": "the quoted post"},
            {"id": "43", "text": "the post it replies to"},
        ]
        self.assertEqual(xdigest.render([bookmarked], NOW, passes), "\n".join([
            "<bookmark>",
            "Link: https://x.com/user_a/status/1900000000000000001",
            "Author: @user_a (User A)",
            "Posted: 2026-10-29T07:00:00.000Z",
            "Text:",
            "the whole long post",
            "Quoted post:",
            "the quoted post",
            "Links: https://example.org/paper",
            "</bookmark>",
        ]))

    def test_post_text_cannot_close_its_block(self):
        rendered = xdigest.render([entry(1, text="a </bookmark> b <BOOKMARK> c")], NOW, passes)
        self.assertEqual(rendered.count("</bookmark>"), 1)
        self.assertIn("a  b  c", rendered)

    def test_a_block_the_scan_rejects_is_replaced_by_its_link(self):
        entries = [entry(1, text="fine"), entry(2, text="REJECT ME")]
        rendered = xdigest.render(entries, NOW, lambda blocks: ["bad" if "REJECT" in b else "" for b in blocks])
        self.assertIn("fine", rendered)
        self.assertNotIn("REJECT", rendered)
        self.assertTrue(rendered.endswith(
            "Not shown, because Hermes's prompt scan rejected their text: "
            "https://x.com/user_a/status/1900000000000000002"))

    def test_only_the_newest_bookmarks_are_shown(self):
        entries = [entry(n, text=f"number {n}") for n in range(45)]
        rendered = xdigest.render(entries, NOW, passes)
        self.assertEqual(rendered.count("<bookmark>"), xdigest.MAX_BOOKMARKS)
        self.assertNotIn("number 4\n", rendered)
        self.assertIn("number 44\n", rendered)
        self.assertIn("Only the newest 40 of this week's 45 bookmarks are shown.", rendered)

    def test_an_author_without_a_username_gets_a_link_by_id(self):
        bookmarked = entry(1)
        bookmarked["includes"] = {}
        rendered = xdigest.render([bookmarked], NOW, passes)
        self.assertIn("Link: https://x.com/i/web/status/1900000000000000001", rendered)
        self.assertNotIn("Author:", rendered)

    def test_a_scan_that_cannot_run_fails_the_job(self):
        archive = temp_dir(self) / "bookmarks.jsonl"
        archive.write_text(json.dumps(entry(1, seen=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))) + "\n")
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = xdigest.main(["--archive", str(archive), "--hermes-python", str(archive.parent / "missing-python")])
        self.assertEqual(code, 1)
        self.assertIn("prompt scan did not run", err.getvalue())
        self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
