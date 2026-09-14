#!/usr/bin/env python3
# Builds the synthetic dictation corpus, writes jobs for `uttrflow-dev bench`, and scores a run. See Docs/performance.md.
import argparse, array, json, math, os, random, re, statistics, subprocess, sys, unicodedata, wave
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, ".build", "bench")
ENGLISH = ["Samantha", "Daniel", "Rishi"]  # US, UK and Indian English
PAUSE = " [[slnc 900]] "

POOL = [
    "The garden needs water before noon.", "Please send the draft to the design team by Friday.",
    "We moved the weekly meeting to the small room on the third floor.",
    "The blue folder holds last month's invoices and the new supplier list.",
    "Remind me to call the plumber about the kitchen sink tomorrow morning.",
    "The train was late again, so the workshop started twenty minutes behind schedule.",
    "Add three boxes of paper clips and a stapler to the office order.",
    "The report says sales grew slowly in the spring and faster over the summer.",
    "Can you check whether the projector in the main hall still works?",
    "The recipe calls for two cups of flour, one egg and a pinch of salt.",
    "Our flight lands at seven, and the hotel is a short taxi ride away.",
    "The new version fixes the crash when the window is resized quickly.",
    "Let's review the budget next Tuesday after lunch.",
    "The children painted the fence bright yellow over the long weekend.",
    "Water the tomatoes, feed the cat, and lock the back door before leaving.",
    "The library closes early on public holidays, so plan your visit around that.",
    "He wrote the whole chapter in one sitting and then rewrote the ending twice.",
    "The bakery on the corner sells fresh bread until the early afternoon.",
    "We need a volunteer to take notes during the quarterly planning session.",
    "The storm knocked out power for most of the street for about an hour.",
    "Bring a warm jacket, because the evening wind near the lake gets very cold.",
    "The package should arrive on Thursday unless the courier is delayed again.",
    "Please rename the file so the date comes first and the project name second.",
    "The museum added a new wing for modern sculpture and old maps.",
    "The team agreed to ship the smaller change first and measure the result.",
    "I think the onboarding checklist is too long for people who only need read access.",
    "Could you move the design review to Thursday so the contractors can join?",
    "The dashboard loads slowly on older laptops, and the charts flicker when you scroll.",
    "Nobody has touched the backup script in months, which worries me a little.",
    "Let's keep the release notes short and link to the longer guide instead.",
    "The printer on the second floor jams whenever someone uses the thick card stock.",
    "I would rather fix the flaky test properly than retry it three times.",
    "The quarterly survey closes on Monday, so please remind your teams today.",
    "We should archive the old channels before the new members arrive next week.",
    "The heating in the east wing turns on too early and wastes a lot of energy.",
    "Please double check the shipping address before you confirm the order.",
    "The interns finished the prototype early and started writing documentation.",
    "Our support queue doubled after the update, mostly with questions about login.",
    "I left the spare keys with the front desk in a small brown envelope.",
    "The workshop ran long, but everyone agreed the second half was worth it.",
]

REPLIES = [("Okay", "Okay."), ("Thank you", "Thank you."), ("Sounds good", "Sounds good."),
           ("Call me back", "Call me back."), ("Ship it", "Ship it."), ("Not today", "Not today."),
           ("See you tomorrow", "See you tomorrow."), ("Yes please", "Yes please."),
           ("Are you free?", "Are you free?"), ("What time?", "What time?"), ("Really?", "Really?"),
           ("Can you call me?", "Can you call me?"), ("Almost done.", "Almost done."),
           ("Running late, sorry.", "Running late, sorry.")]

NUMBERS = [
    "The invoice comes to 4,250 dollars and 75 cents, due on the 12th of March.",
    ("Our conversion rate went from 3.5 percent to 4.2 percent in 6 weeks.",
     "Our conversion rate went from 3.5% to 4.2% in 6 weeks."),
    "Set the timeout to 250 milliseconds and retry 3 times before failing.",
    "The meeting starts at 9:45 and the flight number is 447.",
]
EMAILS = [
    ("Please send the contract to priya dot shah at example dot com by tonight.",
     "Please send the contract to priya.shah@example.com by tonight."),
    ("My work address is ops dash team at mail dot example dot org.", "My work address is ops-team@mail.example.org."),
    ("Forward the logs to support at example dot com and copy j dot rivera at example dot net.",
     "Forward the logs to support@example.com and copy j.rivera@example.net."),
]
CODE = [
    ("Rename the function get user by ID to fetch user and update every call site.",
     "Rename the function getUserById to fetchUser and update every call site."),
    ("Set max retries to five in the config file and restart the worker.",
     "Set max_retries to 5 in the config file and restart the worker."),
    ("The bug is in parse JSON response, which returns null when the array is empty.",
     "The bug is in parseJsonResponse, which returns null when the array is empty."),
    ("Run npm install, then open source slash app dot tsx and check the use effect hook.",
     "Run npm install, then open src/app.tsx and check the useEffect hook."),
]
NOUNS = [
    ("Zorvane Kelthmar will meet Pravix and Quennel at the Velbrook office on Friday.",
     ["Zorvane", "Kelthmar", "Pravix", "Quennel", "Velbrook"]),
    ("Ask Mirvella Ostrander whether the Tashiro account moved to Dorimat last week.",
     ["Mirvella", "Ostrander", "Tashiro", "Dorimat"]),
    ("The Jaxvale release depends on Brunmore, so tell Cendrik before we ship Fyloria.",
     ["Jaxvale", "Brunmore", "Cendrik", "Fyloria"]),
]
HINGLISH = [
    "Kal ki meeting cancel ho gayi hai, toh hum report Monday ko bhejenge.",
    "Yaar, mera laptop bahut slow chal raha hai, kya tum IT team ko ticket bhej sakte ho?",
    "Aaj office mein bahut kaam hai, lekin shaam ko main gym zaroor jaunga.",
]
PUNCTUATION = [
    ("Dear team comma the build is green full stop", "Dear team, the build is green."),
    ("Can you join the call at noon question mark", "Can you join the call at noon?"),
    ("Buy milk comma eggs comma and bread new line call the landlord", "Buy milk, eggs, and bread\nCall the landlord"),
]
CORRECTIONS = [
    ("Let's meet at four no sorry at five on Thursday.", "Let's meet at five on Thursday."),
    ("Send the file to Marta, I mean to Joanna, before lunch.", "Send the file to Joanna before lunch."),
    ("Um so I think uh we should ship the smaller fix first.", "So I think we should ship the smaller fix first."),
    ("Book a table for six, actually eight, at the usual place.", "Book a table for eight at the usual place."),
]
VARIANT_BASES = ["d15-samantha", "d15-daniel", "d15-rishi", "d30-samantha", "reply1-daniel", "reply4-daniel",
                 "numbers1-daniel", "code0-samantha", "tc-en-people-rishi", "tc-hi-everyday-lekha"]


def passage(seconds, start, paused):
    """Sentences from the pool until the passage reads for about `seconds`, with a breath every third sentence."""
    chosen, words, i = [], 0, start
    while words < int(seconds * 2.75):
        chosen.append(POOL[i % len(POOL)]); words += len(POOL[i % len(POOL)].split()); i += 1
    said = "".join(s + (PAUSE if paused and k % 3 == 2 and k < len(chosen) - 1 else " ") for k, s in enumerate(chosen))
    return said.strip(), " ".join(chosen)


def committed_passages():
    """The committed TranscriptionCorpus passages, read out of the Swift source."""
    src = open(os.path.join(ROOT, "Sources", "UttrflowEval", "TranscriptionCorpus.swift")).read()

    def literal(text):
        lines = text.split("\n")[1:-1]
        indent = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
        return "\n".join(l[indent:] for l in lines).replace("\\\n", "").replace("\\'", "'")

    found = []
    for m in re.finditer(r'\.init\(\s*id: "([^"]+)", language: \.(\w+), stressor: \.(\w+),(.*?)\n        \)', src, re.S):
        fields = {f: literal(x.group(1)) for f in ("romanised", "devanagari")
                  for x in [re.search(f + r': (""".*?""")', m.group(4), re.S)] if x}
        found.append(dict(id=m.group(1), language=m.group(2), stressor=m.group(3), **fields))
    return found


def clips():
    out = []

    def add(cid, category, language, voice, say, written, spoken=None, vocabulary=(), devanagari=None):
        out.append(dict(id=cid, category=category, language=language, voice=voice, say=say, spoken=spoken or say,
                        written=written, vocabulary=list(vocabulary), variant="clean", devanagari=devanagari))

    for i, (said, written) in enumerate(REPLIES):
        add(f"reply{i}-{ENGLISH[i % 3].lower()}", "reply", "english", ENGLISH[i % 3], said, written)
    for seconds in (5, 15, 30, 60, 120):
        for k, voice in enumerate(ENGLISH):
            said, written = passage(seconds, 7 * k + seconds, paused=seconds >= 30)
            add(f"d{seconds}-{voice.lower()}", f"dur{seconds}", "english", voice, said, written, spoken=written)
    said, written = passage(60, 3, paused=False)
    add("d60-nopause-samantha", "dur60", "english", "Samantha", said, written, spoken=written)
    for name, rows in (("numbers", NUMBERS), ("emails", EMAILS), ("code", CODE), ("punctuation", PUNCTUATION),
                       ("selfcorrection", CORRECTIONS)):
        for i, row in enumerate(rows):
            said, written = (row, row) if isinstance(row, str) else row
            add(f"{name}{i}-{ENGLISH[i % 3].lower()}", name, "english", ENGLISH[i % 3], said, written)
    for i, (said, words) in enumerate(NOUNS):
        for voice in ENGLISH:
            add(f"nouns{i}-{voice.lower()}", "nouns", "english", voice, said, said)
            add(f"nouns{i}-{voice.lower()}-vocabulary", "nouns-vocabulary", "english", voice, said, said, vocabulary=words)
    for i, said in enumerate(HINGLISH):
        add(f"hinglish{i}-rishi", "hinglish-latin", "hinglish", "Rishi", said, said)
    for case in committed_passages():
        if case["language"] == "english":
            for voice in ENGLISH:
                add(f"tc-{case['id']}-{voice.lower()}", f"tc-{case['stressor']}", "english", voice,
                    case["romanised"], case["romanised"])
        else:
            add(f"tc-{case['id']}-lekha", f"tc-{case['language']}", case["language"], "Lekha", case["devanagari"],
                case["romanised"], spoken=case["romanised"], devanagari=case["devanagari"])
    return out


def read_wav(path):
    w = wave.open(path); samples = array.array("h", w.readframes(w.getnframes())); w.close(); return samples


def write_wav(path, samples):
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(samples.tobytes()); w.close()


def noisy(snr_db, seed):
    """Brown noise at `snr_db` below the speech's power, closer to a room than white noise is."""
    def mix(samples):
        rng = random.Random(seed)
        power = sum(x * x for x in samples) / max(1, len(samples))
        scale = math.sqrt(power / (10 ** (snr_db / 10))) * 0.35
        out, level = array.array("h"), 0.0
        for x in samples:
            level = 0.97 * level + rng.gauss(0, 1)
            out.append(max(-32768, min(32767, int(x + level * scale))))
        return out
    return mix


def gain(db):
    k = 10 ** (db / 20)
    return lambda samples: array.array("h", (max(-32768, min(32767, int(x * k))) for x in samples))


def corpus(args):
    audio = os.path.join(args.out, "audio"); os.makedirs(audio, exist_ok=True)
    made = clips()
    for c in made:
        c["wav"] = os.path.join(audio, c["id"] + ".wav")
        if not os.path.exists(c["wav"]):
            subprocess.run(["say", "-v", c["voice"], "-o", c["wav"], "--file-format=WAVE",
                            "--data-format=LEI16@16000", c["say"]], check=True)
    for c in [c for c in made if c["id"] in VARIANT_BASES]:
        for name, change in (("snr20", noisy(20, 1)), ("snr10", noisy(10, 2)), ("quiet", gain(-24)), ("hot", gain(12))):
            v = dict(c, id=f"{c['id']}-{name}", variant=name, wav=os.path.join(audio, f"{c['id']}-{name}.wav"))
            if not os.path.exists(v["wav"]):
                write_wav(v["wav"], change(read_wav(c["wav"])))
            made.append(v)
    for c in made:
        w = wave.open(c["wav"]); c["duration"] = w.getnframes() / w.getframerate(); w.close()
    json.dump(made, open(os.path.join(args.out, "corpus.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{len(made)} clips, {sum(c['duration'] for c in made) / 60:.1f} min of speech, in {args.out}")


def jobs(args):
    made = json.load(open(os.path.join(args.out, "corpus.json")))
    chosen = [c for c in made if not args.categories or c["category"] in args.categories.split(",")]
    if args.clean_only:
        chosen = [c for c in chosen if c["variant"] == "clean"]
    lines = []
    for _ in range(args.repeat):
        for c in chosen:
            for cleaner in args.cleaners.split(","):
                lines.append("\t".join([c["id"], c["wav"], ",".join(c["vocabulary"]), args.mode, cleaner]))
    sys.stdout.write("\n".join(lines) + "\n")


ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()
ORDINALS = {"first": "one", "second": "two", "third": "three", "fourth": "four", "fifth": "five", "sixth": "six",
            "seventh": "seven", "eighth": "eight", "ninth": "nine", "tenth": "ten", "eleventh": "eleven",
            "twelfth": "twelve", "twentieth": "twenty"}


def spelled(n):
    if n < 20: return ONES[n]
    if n < 100: return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    if n < 1000: return ONES[n // 100] + " hundred" + ("" if n % 100 == 0 else " " + spelled(n % 100))
    if n < 1_000_000: return spelled(n // 1000) + " thousand" + ("" if n % 1000 == 0 else " " + spelled(n % 1000))
    return " ".join(ONES[int(d)] for d in str(n))


def numeral(m):
    s = m.group(0).replace(",", "")
    if ":" in s:
        h, mi = s.split(":"); return spelled(int(h)) + " " + (spelled(int(mi)) if int(mi) else "")
    if "." in s:
        whole, part = s.split("."); return spelled(int(whole)) + " point " + " ".join(ONES[int(d)] for d in part)
    return spelled(int(s))


def normalise(text):
    """Words for a word error rate: numbers spelled, identifiers and addresses split, case and punctuation gone."""
    t = unicodedata.normalize("NFC", text)
    t = re.sub(r"(\S+)@(\S+)", lambda m: (m.group(1) + " at " + m.group(2)).replace("-", " dash "), t)
    t = re.sub(r"([a-z])([A-Z])", r"\1 \2", t)
    t = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", t)
    t = t.lower().replace("_", " ").replace("%", " percent").replace("/", " slash ")
    t = re.sub(r"(?<=[a-z])\.(?=[a-z])", " dot ", t)
    t = re.sub(r"(\d)(st|nd|rd|th)\b", r"\1", t)
    t = re.sub(r"\d[\d,]*(?:[.:]\d+)?", numeral, t)
    t = re.sub(r"[^\w\s]", " ", t.replace("'", "").replace("’", ""))
    return [ORDINALS.get(w, w) for w in t.split()]


def edits(ref, hyp):
    row = list(range(len(hyp) + 1))
    for i in range(1, len(ref) + 1):
        prev, row[0] = row[:], i
        for j in range(1, len(hyp) + 1):
            row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (ref[i - 1] != hyp[j - 1]))
    return row[len(hyp)]


def errors(references, hypothesis):
    """The fewest edits against any of the references, with that reference's length."""
    h = normalise(hypothesis)
    scored = [(edits(normalise(r), h), len(normalise(r))) for r in references if r]
    return min(scored, key=lambda x: x[0] / max(1, x[1]))


def percentile(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))] if values else float("nan")


def score(args):
    made = {c["id"]: c for c in json.load(open(os.path.join(args.out, "corpus.json")))}
    rows = []
    for line in open(args.run):
        if line.startswith("BENCH "):
            event = json.loads(line[6:])
            if event["event"] == "loaded":
                print(f"model loaded in {event['seconds']:.1f} s, {event['cpu']:.1f} processor-seconds")
            elif event["event"] == "result" and event["id"] in made:
                rows.append(event)
    scored = []
    for r in rows:
        c = made[r["id"]]
        heard = [e for e in r["events"] if e["kind"] == "asr"]
        tidied = [e for e in r["events"] if e["kind"] == "clean"]
        key_up = next(float(e["t"]) for e in r["events"] if e["kind"] == "keyup")
        early = [float(e["t1"]) for e in tidied if float(e["t1"]) <= key_up]
        raw_e, raw_n = errors([c["spoken"], c.get("devanagari")], " ".join(e["text"] for e in heard))
        out_e, out_n = errors([c["written"], c.get("devanagari")], r.get("text", ""))
        scored.append(dict(r=r, c=c, raw=(raw_e, raw_n), out=(out_e, out_n), first_early=min(early) if early else None,
                           asr=sum(float(e["t1"]) - float(e["t0"]) for e in heard),
                           tidy=sum(float(e["t1"]) - float(e["t0"]) for e in tidied)))

    def wer_table(title, key, keep):
        groups = defaultdict(list)
        for s in scored:
            if keep(s): groups[key(s)].append(s)
        print(f"\n{title}\n\n| | clips | raw WER | final WER |\n|---|---|---|---|")
        for k in sorted(groups):
            g = groups[k]
            raw = sum(s["raw"][0] for s in g) / max(1, sum(s["raw"][1] for s in g))
            out = sum(s["out"][0] for s in g) / max(1, sum(s["out"][1] for s in g))
            print(f"| {k} | {len(g)} | {100 * raw:.1f}% | {100 * out:.1f}% |")

    for cleaner in sorted({s["r"]["cleaner"] for s in scored}):
        for mode in sorted({s["r"]["mode"] for s in scored}):
            mine = lambda s, cl=cleaner, m=mode: s["r"]["cleaner"] == cl and s["r"]["mode"] == m
            if not any(mine(s) for s in scored): continue
            print(f"\n## cleaner {cleaner}, mode {mode}")
            wer_table("Word error rate by category, clean audio", lambda s: s["c"]["category"],
                      lambda s: mine(s) and s["c"]["variant"] == "clean")
            wer_table("Word error rate by language and voice, clean audio", lambda s: f"{s['c']['language']}, {s['c']['voice']}",
                      lambda s: mine(s) and s["c"]["variant"] == "clean")
            wer_table("Word error rate by audio variant, over the variant bases", lambda s: s["c"]["variant"],
                      lambda s: mine(s) and (s["c"]["id"] in VARIANT_BASES or s["c"]["id"].rsplit("-", 1)[0] in VARIANT_BASES))
            groups = defaultdict(list)
            for s in scored:
                if mine(s) and s["c"]["variant"] == "clean":
                    cat = s["c"]["category"]
                    groups[cat if cat == "reply" or cat.startswith("dur") else
                           "other, Hindi" if s["c"]["language"] != "english" else "other, English"].append(s)
            print("\nCost, clean audio\n\n| | clips | speech s | wait p50 | wait p95 | first early piece p50 | "
                  "recognising p50 | tidying p50 | processor s per speech s | peak footprint MB |")
            print("|---|---|---|---|---|---|---|---|---|---|")
            for k in sorted(groups):
                g = groups[k]
                waits = [s["r"]["wait"] for s in g]
                early = [s["first_early"] for s in g if s["first_early"] is not None]
                cells = [len(g), f"{statistics.mean(s['r']['audio'] for s in g):.1f}", f"{percentile(waits, 50):.2f}",
                         f"{percentile(waits, 95):.2f}", f"{percentile(early, 50):.1f}" if early else "—",
                         f"{percentile([s['asr'] for s in g], 50):.2f}", f"{percentile([s['tidy'] for s in g], 50):.2f}",
                         f"{sum(s['r']['cpu'] for s in g) / sum(s['r']['audio'] for s in g):.3f}",
                         f"{max(s['r']['peakMB'] for s in g):.0f}"]
                print(f"| {k} | " + " | ".join(str(x) for x in cells) + " |")
    failed = [(s["r"]["id"], s["r"]["failed"]) for s in scored if s["r"].get("failed")]
    print(f"\nfailed: {failed or 'none'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT, help="where the corpus lives (default .build/bench)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("corpus", help="synthesise the corpus with say")
    j = sub.add_parser("jobs", help="print a jobs file for uttrflow-dev bench")
    j.add_argument("--mode", default="fast", choices=["fast", "rt"])
    j.add_argument("--cleaners", default="shipping", help="comma-separated: shipping, rules")
    j.add_argument("--categories", default="", help="comma-separated categories, all when empty")
    j.add_argument("--clean-only", action="store_true", help="leave out the noise and gain variants")
    j.add_argument("--repeat", type=int, default=1)
    s = sub.add_parser("score", help="score the output of uttrflow-dev bench")
    s.add_argument("run")
    args = parser.parse_args()
    {"corpus": corpus, "jobs": jobs, "score": score}[args.command](args)


if __name__ == "__main__":
    main()
