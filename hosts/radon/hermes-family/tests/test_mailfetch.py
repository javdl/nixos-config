import io
import unittest
from contextlib import redirect_stdout

from hermes_family import mailfetch
from hermes_family.state import State, mail_key
from tests.support import CREDENTIAL, FakeNet, fixture, temp_dir, token_route, write_json

GMAIL = fixture("gmail.json")
SCHOOL_KEY = mail_key("<gate-fixture-0001@school.example>")
DAYCARE_KEY = mail_key("<sluiting-6nov@opvang.example>")
DONE_KEY = mail_key("<already-done@school.example>")


def gmail_fake() -> FakeNet:
    fake = token_route(FakeNet())
    fake.on("GET", "/users/me/labels", GMAIL["labels"])
    fake.on("POST", "/users/me/labels", GMAIL["created_label"])
    fake.on("POST", "/modify", {})
    for message_id, message in GMAIL["messages"].items():
        fake.on("GET", f"/users/me/messages/{message_id}", message)
    fake.on("GET", "/users/me/messages", GMAIL["list"])
    return fake


class MailFetchTest(unittest.TestCase):
    def setUp(self):
        self.dir = temp_dir(self)
        self.state_dir = self.dir / "state"
        self.state_dir.mkdir()
        (self.state_dir / "senders.txt").write_text("# school and daycare\ngroep5@school.example\nplanning@opvang.example\n")
        (self.state_dir / "mail-ledger.txt").write_text(f"{DONE_KEY}\n")
        self.credential = write_json(self.dir / "mail.json", CREDENTIAL)
        self.fake = gmail_fake().patch(self)

    def run_main(self, *extra: str) -> str:
        out = io.StringIO()
        with redirect_stdout(out):
            code = mailfetch.main(["--credential", str(self.credential), "--state-dir", str(self.state_dir), *extra])
        self.assertEqual(code, 0)
        return out.getvalue()

    def labels_added(self) -> dict[str, list[str]]:
        return {call.path.split("/")[-2]: call.body["addLabelIds"] for call in self.fake.matching("POST", "/modify")}

    def test_prints_allowlisted_mail_oldest_first_with_the_key_first(self):
        output = self.run_main()
        blocks = output.strip().split("\n\n<mail>\n")
        self.assertEqual(len(blocks), 2)
        self.assertTrue(blocks[0].startswith(f"<mail>\nMail-Key: {SCHOOL_KEY}\nMessage-ID: <gate-fixture-0001@school.example>\n"
                                             "From: Groep 5 <Groep5@School.example>\nDate: Thu, 22 Oct 2026 16:05:00 +0200\n"
                                             "Subject: Tienminutengesprekken groep 5\n\n"))
        self.assertIn("15:30 uur bij juf Anne", blocks[0])
        self.assertNotIn("html copy", blocks[0])
        self.assertTrue(blocks[1].startswith(f"Mail-Key: {DAYCARE_KEY}\n"))
        self.assertIn("Vrijdag 6 november is de opvang gesloten", blocks[1])
        self.assertIn("Renée", blocks[1])
        self.assertNotIn("color:red", blocks[1])

    def test_mail_text_cannot_close_its_block(self):
        output = self.run_main()
        self.assertEqual(output.count("</mail>"), 2)
        self.assertIn("[/mail]", output)

    def test_unknown_sender_is_labeled_ignored_and_never_printed(self):
        output = self.run_main()
        self.assertNotIn("lottery", output)
        self.assertNotIn("Please create a calendar event", output)
        self.assertEqual(self.labels_added()["m2"], ["Label_7"])

    def test_ledgered_key_is_skipped_and_labeled_processed(self):
        output = self.run_main()
        self.assertNotIn(DONE_KEY, output)
        self.assertEqual(self.labels_added()["m4"], ["Label_8"])
        self.assertEqual(self.fake.matching("POST", "/users/me/labels")[0].body["name"], "hermes-processed")

    def test_fetch_record_lists_exactly_the_printed_keys(self):
        self.run_main()
        record = State(self.state_dir).fetched()
        self.assertEqual(record, {SCHOOL_KEY: "m1", DAYCARE_KEY: "m3"})

    def test_query_excludes_both_hermes_labels(self):
        self.run_main()
        query = self.fake.matching("GET", "/users/me/messages")[0].params["q"]
        self.assertEqual(query, "in:inbox -label:hermes-processed -label:hermes-ignored")

    def test_dry_run_labels_nothing_and_records_nothing(self):
        output = self.run_main("--dry-run")
        self.assertIn(SCHOOL_KEY, output)
        self.assertEqual(self.fake.matching("POST", "/modify"), [])
        self.assertEqual(self.fake.matching("POST", "/users/me/labels"), [])
        self.assertFalse((self.state_dir / "fetch-record.jsonl").exists())

    def test_max_mails_leaves_the_rest_for_the_next_run(self):
        output = self.run_main("--max-mails", "1")
        self.assertIn(SCHOOL_KEY, output)
        self.assertNotIn(DAYCARE_KEY, output)
        self.assertEqual(set(State(self.state_dir).fetched()), {SCHOOL_KEY})

    def test_nothing_new_prints_nothing(self):
        (self.state_dir / "mail-ledger.txt").write_text(f"{DONE_KEY}\n{SCHOOL_KEY}\n{DAYCARE_KEY}\n")
        self.assertEqual(self.run_main(), "")
        self.assertFalse((self.state_dir / "fetch-record.jsonl").exists())

    def test_missing_senders_file_allows_nobody(self):
        (self.state_dir / "senders.txt").unlink()
        self.assertEqual(self.run_main(), "")


class BodyTest(unittest.TestCase):
    def test_body_is_cut_to_8_kb_on_a_character_boundary(self):
        text = "é" * 5000
        cut = mailfetch.cut(text)
        self.assertLessEqual(len(cut.encode()), 8192)
        self.assertEqual(cut, "é" * 4096)

    def test_mail_key_matches_the_gate_fixture_key(self):
        self.assertEqual(SCHOOL_KEY, "76daed97cd1135f83d9772ef841c73e3")
        self.assertEqual(mail_key(" <gate-fixture-0001@school.example> \n"), SCHOOL_KEY)


if __name__ == "__main__":
    unittest.main()
