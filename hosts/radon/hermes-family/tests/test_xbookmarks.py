import io
import json
import re
import urllib.parse
import unittest
from contextlib import redirect_stderr, redirect_stdout

from hermes_family import xbookmarks
from tests.support import FakeNet, temp_dir, write_json

# Made up, like every value in these tests.
CREDENTIAL = {
    "X_API_KEY": "key-example-000",
    "X_API_KEY_SECRET": "key-secret-example-111",
    "X_ACCESS_TOKEN": "2001-token-example-222",
    "X_ACCESS_TOKEN_SECRET": "token-secret-example-333",
    "X_USER_ID": "2001",
    "X_USERNAME": "voorbeeld",
}
BOOKMARKS = "/2/users/2001/bookmarks"


def post_id(n: int) -> str:
    return str(1900000000000000000 + n)


def make_post(n: int) -> dict:
    """Bookmark n, where 0 is the newest, in the shape the API answered on 2026-10-25."""
    return {
        "id": post_id(n),
        "text": f"post {n}",
        "edit_history_tweet_ids": [post_id(n)],
        "author_id": str(3000 + n % 4),
        "created_at": "2026-10-20T08:00:00.000Z",
        "attachments": {"media_keys": [f"3_{n}"]},
    }


class FakeX:
    """GET /2/users/2001/bookmarks over a list of posts, newest first. A hidden slot counts
    toward max_results but is not returned; a detail-hidden post is missing only from
    responses with expansions; `before` runs before the nth request is answered."""

    def __init__(self, count: int, *, hidden_slots=(), detail_hidden=(), before=None):
        self.posts = [make_post(n) for n in range(count)]
        self.hidden_slots = set(hidden_slots)
        self.detail_hidden = set(detail_hidden)
        self.before = before
        self.requests = 0

    def __call__(self, call):
        self.requests += 1
        if self.before:
            self.before(self, self.requests)
        size = int(call.params["max_results"])
        start = int(call.params.get("pagination_token", "page-0").removeprefix("page-"))
        detailed = "expansions" in call.params
        chunk = [
            post for slot, post in enumerate(self.posts[start:start + size], start)
            if slot not in self.hidden_slots and not (detailed and post["id"] in self.detail_hidden)
        ]
        body = {
            "data": [post if detailed else {key: post[key] for key in ("id", "text", "edit_history_tweet_ids")}
                     for post in chunk],
            "meta": {"result_count": len(chunk)},
        }
        if start + size < len(self.posts):
            body["meta"]["next_token"] = f"page-{start + size}"
        if detailed:
            authors = sorted({post["author_id"] for post in chunk})
            body["includes"] = {
                "users": [{"id": a, "username": f"user_{a}", "name": f"User {a}"} for a in authors],
                "media": [{"media_key": post["attachments"]["media_keys"][0], "type": "photo",
                           "url": "https://pbs.example/x.jpg"} for post in chunk],
            }
        return body


def parse_oauth(header: str) -> dict[str, str]:
    assert header.startswith("OAuth "), header
    return {urllib.parse.unquote(k): urllib.parse.unquote(v)
            for k, v in re.findall(r'([\w%.-]+)="([^"]*)"', header)}


class XBookmarksTest(unittest.TestCase):
    def setUp(self):
        self.dir = temp_dir(self)
        self.credential = self.dir / "credential.env"
        self.credential.write_text("".join(f"{k}={v}\n" for k, v in CREDENTIAL.items()))
        self.archive = self.dir / "x-bookmarks" / "bookmarks.jsonl"
        self.import_dir = self.dir / "import"
        self.fake = FakeNet()

    def serve(self, responder) -> FakeNet:
        return self.fake.on("GET", BOOKMARKS, responder).patch(self)

    def run_main(self, *, import_dir: bool = False) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        argv = ["--credential", str(self.credential), "--archive", str(self.archive)]
        if import_dir:
            argv += ["--import-dir", str(self.import_dir)]
        with redirect_stdout(out), redirect_stderr(err):
            code = xbookmarks.main(argv)
        return code, out.getvalue(), err.getvalue()

    def entries(self) -> list[dict]:
        return [json.loads(line) for line in self.archive.read_text().splitlines()]

    def store(self, numbers) -> None:
        """An archive from earlier runs, the first of which was the backfill."""
        self.archive.parent.mkdir(parents=True, exist_ok=True)
        self.archive.write_text("".join(
            json.dumps({"id": post_id(n), "via": "poll", "first_seen_at": "2026-10-01T00:00:00Z"}) + "\n"
            for n in numbers))
        (self.archive.parent / xbookmarks.BACKFILL_MARKER).write_text("2026-09-01T00:00:00.000000Z\n")

    def test_signature_matches_the_example_in_xs_documentation(self):
        credential = xbookmarks.Credential(
            "xvz1evFS4wEEPTGEFPHBog", "kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw",
            "370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb", "LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE", "370773112")
        header = xbookmarks.oauth1_header(
            "POST", "https://api.x.com/1.1/statuses/update.json",
            {"include_entities": "true", "status": "Hello Ladies + Gentlemen, a signed OAuth request!"},
            credential, nonce="kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg", timestamp=1318622958)
        self.assertEqual(parse_oauth(header)["oauth_signature"], "Ls93hJiZbQ3akF3HF3x1Bz8/zU4=")

    def test_every_request_is_signed_over_the_parameters_it_sends(self):
        self.serve(FakeX(150))
        self.assertEqual(self.run_main()[0], 0)
        credential = xbookmarks.load_credential(self.credential)
        self.assertGreaterEqual(len(self.fake.calls), 3)
        for call in self.fake.calls:
            oauth = parse_oauth(call.headers["Authorization"])
            expected = xbookmarks.oauth1_header("GET", call.url, call.params, credential,
                                                nonce=oauth["oauth_nonce"], timestamp=int(oauth["oauth_timestamp"]))
            self.assertEqual(oauth, parse_oauth(expected), call.params)
            self.assertEqual(oauth["oauth_token"], CREDENTIAL["X_ACCESS_TOKEN"])

    def test_first_run_stores_every_bookmark_the_api_returns_oldest_first(self):
        self.serve(FakeX(150))
        code, out, err = self.run_main(import_dir=True)
        self.assertEqual((code, err), (0, ""))
        probe, *walk = self.fake.calls
        self.assertEqual(probe.params, {"max_results": "10"})
        self.assertEqual([c.params["max_results"] for c in walk], ["90", "90"])
        self.assertEqual(walk[1].params["pagination_token"], "page-90")
        entries = self.entries()
        self.assertEqual([e["id"] for e in entries], [post_id(n) for n in reversed(range(150))])
        self.assertEqual({e["via"] for e in entries}, {"backfill"})
        self.assertEqual(entries[-1]["includes"]["users"], [{"id": "3000", "username": "user_3000", "name": "User 3000"}])
        self.assertEqual([m["media_key"] for m in entries[-1]["includes"]["media"]], ["3_0"])
        self.assertIn("stored the 150 bookmarks", out)
        self.assertIn(str(self.import_dir), out)

    def test_an_ordinary_run_with_nothing_new_fetches_only_ids_and_prints_nothing(self):
        self.serve(FakeX(30))
        self.store(range(30))
        before = self.archive.read_bytes()
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params for c in self.fake.calls], [{"max_results": "10"}])
        self.assertEqual(self.archive.read_bytes(), before)

    def test_new_bookmarks_are_fetched_down_to_the_last_unknown_one(self):
        self.serve(FakeX(30))
        self.store([2, 3] + list(range(5, 30)))
        self.assertEqual(self.run_main(), (0, "", ""))
        detail = self.fake.calls[1].params
        self.assertEqual(detail["max_results"], "5")
        self.assertIn("note_tweet", detail["tweet.fields"])
        new = self.entries()[27:]
        self.assertEqual([e["id"] for e in new], [post_id(4), post_id(1), post_id(0)])
        self.assertEqual({e["via"] for e in new}, {"poll"})
        self.assertEqual(new[0]["includes"]["users"][0]["id"], "3000")
        self.assertEqual(new[1]["includes"]["users"][0]["id"], "3001")

    def test_more_new_bookmarks_than_the_probe_holds_are_walked_down_to_a_known_one(self):
        self.serve(FakeX(300))
        self.store(range(25, 300))
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "90"])
        new = self.entries()[275:]
        self.assertEqual([e["id"] for e in new], [post_id(n) for n in reversed(range(25))])
        self.assertEqual({e["via"] for e in new}, {"poll"})

    def test_a_bookmark_added_between_probe_and_detail_does_not_push_a_new_one_out(self):
        def bookmark_during_the_run(fake, request):
            if request == 2:
                fake.posts.insert(0, make_post(100))
        self.serve(FakeX(30, before=bookmark_during_the_run))
        self.store(set(range(30)) - {7})
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "8", "90"])
        new = self.entries()[29:]
        self.assertEqual([e["id"] for e in new], [post_id(7), post_id(100)])
        self.assertEqual([e["includes"]["users"][0]["id"] for e in new], ["3003", "3000"])

    def test_a_bookmark_x_counts_but_does_not_return_does_not_push_a_new_one_out(self):
        self.serve(FakeX(30, hidden_slots={3}))
        self.store(set(range(30)) - {7})
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "7", "90"])
        (new,) = self.entries()[29:]
        self.assertEqual((new["id"], new["includes"]["users"][0]["id"]), (post_id(7), "3003"))

    def test_a_post_only_the_probe_returns_is_stored_as_the_probe_saw_it_once(self):
        self.serve(FakeX(30, detail_hidden={post_id(0)}))
        self.store(range(1, 30))
        self.assertEqual(self.run_main(), (0, "", ""))
        (new,) = self.entries()[29:]
        self.assertEqual((new["id"], new["post"]["text"], new["includes"]), (post_id(0), "post 0", {}))
        calls = len(self.fake.calls)
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params for c in self.fake.calls[calls:]], [{"max_results": "10"}])

    def test_a_lone_surrogate_in_post_text_does_not_stop_the_capture(self):
        fake = FakeX(10)
        fake.posts[0]["text"] = "cut short \ud83d"
        self.serve(fake)
        self.store(range(1, 10))
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual(xbookmarks.read_entries(self.archive)[-1]["post"]["text"], "cut short \ud83d")

    def test_new_bookmarks_below_a_re_bookmarked_archived_post_are_all_stored(self):
        self.serve(FakeX(40))
        self.store([0] + list(range(13, 40)))
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "90"])
        self.assertEqual([e["id"] for e in self.entries()[28:]], [post_id(n) for n in reversed(range(1, 13))])

    def test_a_re_bookmarked_archived_post_at_the_probes_end_does_not_hide_new_ones(self):
        self.serve(FakeX(40))
        self.store([9] + list(range(15, 40)))
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "90"])
        self.assertEqual([e["id"] for e in self.entries()[26:]],
                         [post_id(n) for n in reversed([*range(9), *range(10, 15)])])

    def test_a_raw_line_separator_in_an_archived_line_keeps_the_post_known(self):
        self.serve(FakeX(10))
        self.store(range(1, 10))
        with self.archive.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"id": post_id(0), "post": {"text": "one\u2028two\u2029three\x85"}},
                                    ensure_ascii=False) + "\n")
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([c.params for c in self.fake.calls], [{"max_results": "10"}])
        self.assertEqual(xbookmarks.read_entries(self.archive)[-1]["post"]["text"], "one\u2028two\u2029three\x85")

    def test_an_empty_probe_with_more_pages_is_walked(self):
        self.serve(FakeX(30, hidden_slots=set(range(10))))
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("stored the 20 bookmarks", out)
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "90"])
        self.assertEqual([e["id"] for e in self.entries()], [post_id(n) for n in reversed(range(10, 30))])

    def test_a_probe_showing_one_known_post_is_not_taken_for_the_boundary(self):
        self.serve(FakeX(30, hidden_slots=set(range(9))))
        self.archive.parent.mkdir(parents=True)
        self.archive.write_text(json.dumps({"id": post_id(9), "via": "import", "post": {}}) + "\n")
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("stored the 20 bookmarks", out)
        self.assertEqual([c.params["max_results"] for c in self.fake.calls], ["10", "90"])

    def test_a_probe_only_post_keeps_its_place_among_the_new_ones(self):
        self.serve(FakeX(10, detail_hidden={post_id(0), post_id(2)}))
        self.store(range(5, 10))
        self.assertEqual(self.run_main(), (0, "", ""))
        new = self.entries()[5:]
        self.assertEqual([e["id"] for e in new], [post_id(n) for n in (4, 3, 2, 1, 0)])
        self.assertEqual([bool(e["includes"]) for e in new], [True, True, False, True, False])

    def test_a_first_run_with_no_bookmarks_still_ends_the_backfill(self):
        fake = FakeX(0)
        self.serve(fake)
        code, out, _ = self.run_main()
        self.assertEqual((code, out), (0, "X bookmarks: the first run stored the 0 bookmarks that X's API returned.\n"))
        fake.posts.append(make_post(0))
        self.assertEqual(self.run_main(), (0, "", ""))
        self.assertEqual([(e["id"], e["via"]) for e in self.entries()], [(post_id(0), "poll")])

    def test_an_export_is_imported_while_x_is_unavailable_and_the_backfill_still_follows(self):
        self.serve((402, {"title": "Payment Required", "detail": "credits depleted", "status": 402}))
        self.import_dir.mkdir()
        write_json(self.import_dir / "twitter-Bookmarks-1.json", [{"id": post_id(500), "full_text": "older one"}])
        code, out, err = self.run_main(import_dir=True)
        self.assertEqual(code, 1)
        self.assertIn("imported 1 bookmarks from twitter-Bookmarks-1.json", out)
        self.assertIn("HTTP 402", err)
        self.fake.routes.clear()
        self.fake.on("GET", BOOKMARKS, FakeX(3))
        code, out, _ = self.run_main(import_dir=True)
        self.assertEqual(code, 0)
        self.assertIn("the first run stored the 3 bookmarks", out)
        self.assertEqual([e["via"] for e in self.entries()], ["import", "backfill", "backfill", "backfill"])

    def test_a_failed_request_exits_1_with_xs_reason_and_no_credential(self):
        self.serve((402, {"title": "Payment Required", "detail": "credits depleted", "status": 402}))
        code, out, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("HTTP 402: Payment Required - credits depleted", err)
        for name, value in CREDENTIAL.items():
            if name.endswith(("KEY", "SECRET", "TOKEN")):
                self.assertNotIn(value, out + err)
        self.assertFalse(self.archive.exists())

    def test_a_credential_without_a_key_names_the_key_and_sends_nothing(self):
        self.serve(FakeX(5))
        self.credential.write_text("".join(f"{k}={v}\n" for k, v in CREDENTIAL.items() if k != "X_ACCESS_TOKEN_SECRET"))
        code, out, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("lacks X_ACCESS_TOKEN_SECRET", err)
        self.assertNotIn(CREDENTIAL["X_API_KEY_SECRET"], err)
        self.assertEqual(self.fake.calls, [])

    def test_a_line_cut_short_by_a_crash_is_fetched_again_on_a_line_of_its_own(self):
        self.serve(FakeX(30))
        self.store(range(1, 30))
        with self.archive.open("a") as handle:
            handle.write('{"id": "' + post_id(0) + '", "via": "po')
        self.assertEqual(self.run_main()[0], 0)
        lines = self.archive.read_text().splitlines()
        self.assertEqual(json.loads(lines[-1])["id"], post_id(0))
        self.assertEqual(len(lines), 31)
        self.assertEqual([e["id"] for e in xbookmarks.read_entries(self.archive)][-1], post_id(0))

    def test_an_export_adds_only_unknown_posts_and_is_read_once(self):
        self.serve(FakeX(10))
        self.store(range(10))
        self.import_dir.mkdir()
        write_json(self.import_dir / "twitter-Bookmarks-1761400000000.json", [
            {"id": post_id(500), "full_text": "older one", "screen_name": "user_a", "created_at": "2024-01-02 03:04:05"},
            {"id": post_id(3), "full_text": "already stored", "screen_name": "user_b"},
            {"id": post_id(501), "full_text": "oldest one", "screen_name": "user_c"},
        ])
        code, out, err = self.run_main(import_dir=True)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, "X bookmarks: imported 2 bookmarks from twitter-Bookmarks-1761400000000.json; "
                              "1 were already in the archive.\n")
        imported = self.entries()[10:]
        self.assertEqual([(e["id"], e["via"], e["post"]["full_text"]) for e in imported],
                         [(post_id(500), "import", "older one"), (post_id(501), "import", "oldest one")])
        self.assertEqual(self.run_main(import_dir=True), (0, "", ""))
        self.assertEqual(len(self.entries()), 12)

    def test_a_file_that_is_not_an_export_is_reported_once(self):
        self.serve(FakeX(10))
        self.store(range(10))
        self.import_dir.mkdir()
        write_json(self.import_dir / "notes.json", {"bookmarks": []})
        code, out, _ = self.run_main(import_dir=True)
        self.assertEqual(code, 0)
        self.assertIn("notes.json is not a twitter-web-exporter JSON export", out)
        self.assertEqual(self.run_main(import_dir=True), (0, "", ""))
        self.assertEqual(len(self.entries()), 10)

    def test_a_missing_import_folder_is_not_an_error(self):
        self.serve(FakeX(10))
        self.store(range(10))
        self.assertEqual(self.run_main(import_dir=True), (0, "", ""))


if __name__ == "__main__":
    unittest.main()
