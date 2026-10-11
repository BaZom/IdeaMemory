# Roadmap

Idea Memory: a private place to save things you want to experience later (food, places, films, books, trips…) and find them again. Personal proof of concept; the goal is a phone app.

## Done

- **Accounts:** sign up and sign in with a username and password; each account sees only its own data.
- **Manual ideas:** save an idea with just a title (optional description, category, tags, notes, location and an exact original text), browse newest first, open, edit, delete.

## Next

Each task is small enough to try on the same day. The order can change.

### 004 — Save an idea from a link
Goal: paste a URL, get title/description suggested, review, save.
Done when:
- pasting a link fills the title (and description if the page has one); I can edit before saving
- the original URL is saved and opens from the idea
- if fetching fails, I can still save manually

Not now: screenshots, AI, duplicate detection.
Security-relevant: yes (the server fetches untrusted URLs) → review before merge.

### 005 — Search and filter
Goal: find a saved idea quickly.
Done when:
- one search box matches title, description, tags, notes and location
- a row of category chips filters the collection

Not now: AI search, saved filters.

### 006 — Save an idea from a screenshot
Goal: attach a screenshot to an idea and keep it privately.
Done when:
- I can pick an image when creating an idea; it is shown on the idea
- only my account can see my images; deleting the idea deletes the image

Not now: AI reading the image.
Security-relevant: yes (private file storage) → review before merge.

### 007 — AI suggestions
Goal: fill in an idea's fields from a link or screenshot.
Done when:
- after adding a link or screenshot, suggested fields appear for me to accept or edit
- without AI (outage, no key) everything still works manually

Needs owner approval first: AI provider, what is sent to it, monthly budget.

### 008 — Ask your ideas
Goal: ask “what could we do this weekend?” and get answers from my saved ideas only.
Done when:
- answers refer to my own saved ideas and link to them
- nothing is invented that is not in my ideas

Needs owner approval first (AI, as in 007).

### 009 — On my phone
Goal: open the app on my phone over HTTPS and add it to the home screen.
Done when:
- the app and API run on a hosted service I approved; data stays private
- it works from the iPhone home screen

Needs owner approval first: hosting, region, cost.

## Task format

```text
## NNN — <what I can do afterwards>
Goal: one sentence.
Done when:
- 2–4 things I can check myself
Not now: what is deliberately left out
Security-relevant: yes/no (yes → review before merge)
```

Implementation: simplest design that meets “Done when”, about 3–5 tests (main path, one failure, ownership for a new table or route), `make check`, and a few lines on how to try it.
