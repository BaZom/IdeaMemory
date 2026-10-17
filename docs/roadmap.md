# Roadmap

**Oh, right!** *your little memory*: an external memory for the things you want to experience, on your own and with the people you do things with (your partner, friends, the trip crew), so that when you don’t know what to do, it does. Personal proof of concept; the goal is a phone app.

**Target design:** [oh-app.html](design/oh-app.html), live at https://bazom.github.io/IdeaMemory/design/oh-app.html. Every UI task builds towards it (see [design](design/README.md)).

## What the app is for

1. **Remember for me.** Save something you saw or heard in seconds and stop carrying it in your head.
2. **Help when I don’t know what to do.** Bring back the right saved thing for today or the next few days.
3. **Hold my plans.** Turn a memory into a concrete plan with the details you need on the day.
4. **Do it together.** Share a memory with your partner or a group, see what you all want to do, and plan a date or a trip together. This is one of the app’s biggest features.

## Product principles (owner)

Every task is checked against these. 2–5 are from 2026-10-14; 1 was added on 2026-10-15.

1. **Oh, right! is for you and your people (owner, 2026-10-15).** Besides *Just me* there are shared spaces (a couple, a group of up to 8). Everyone in a space sees and adds to the same memory, says “I’d love to” or “Another time”, and plans together. Spaces are visible from the first screen, as tabs. Nothing is ever a hard no: *Another time* always comes back later. No public profiles, no big groups, no in-app chat.
2. **A little nudge recommends from your memory.** It shows things you can do today or very soon as a small deck of cards (swipe right for yes, left for *Another time*), plus one line for the most urgent thing worth knowing (a plan in the next days, or an event that ends or starts soon). The first page stays calm: tabs, headline, the deck and one or two lines; everything else lives in Planned or My memory. Every item says why it is there (owner, 2026-10-17).
3. **My memory is your database of everything you saved.** Plans live in it too; it must work for someone who forgot the details (browse by kind, person, mood, tags; ask in your own words).
4. **Plans come from memories, never from nowhere.** The memory keeps the *why* (note, who told you, link); the plan adds the *how* (day and time, reminder, where, who’s coming, what to sort out, what to bring). One active plan per memory; when its day passes it becomes a “planned before” line on the memory. No done status. In a shared space the plan is shared: everyone answers *I’m in / Maybe / Can’t*, can help find a day and takes on things to sort out.
5. **Saving asks little and infers a lot.** Only the title is required. Every optional detail switches on a feature (kind → icons and browsing, “good for” → suggestions, dates → “coming soon”, who told you → “Lena’s tip”, link → autofill, tags → your own groups). The app fills in what it can and you correct it; missing details are asked for later, at the right moment.

## The main flow

Your guess “create memory → plan memory → …” is close, but the step in between is what makes the app: memories come back to you.

```mermaid
flowchart LR
    R["<b>Remember</b><br/>save in seconds"]
    M["<b>My memory</b><br/>everything you saved"]
    N["<b>A little nudge</b><br/>what fits today or soon"]
    P["<b>Plan</b><br/>day, time, who,<br/>what to sort out"]
    D(["the day"])

    R --> M
    M --> N
    N -- "Let’s do it" --> P
    N -. "Another time" .-> M
    M -- "plan it" --> P
    R -- "Remember & plan it" --> P
    P --> D
    D -- "planned before" --> M

    classDef step fill:#FFFEFA,stroke:#E0DDCC,color:#24251E
    classDef key fill:#FFEAD1,stroke:#F57908,color:#24251E
    classDef day fill:#F0EBFA,stroke:#7560C0,color:#24251E
    class R,M step
    class N,P key
    class D day
```

- **Remember:** title, plus optional details or a link that fills them in.
- **My memory:** everything, findable without remembering the words (browse, search, ask).
- **A little nudge:** suggests what fits now; *Another time* puts it aside for a while; *Let’s do it* decides.
- **Plan:** becomes concrete on its own page; shows up in Planned, and in the nudge’s “worth knowing” as the day comes closer.
- **After the day:** back in the memory with a history line; the memory may be suggested again later, planned again, or let go.

Two shortcuts: you can open any memory from My memory and plan it directly, and *Remember & plan it* saves and plans in one go.

**Together** (in a shared space), the same flow with one extra step (adding something is suggesting it): the nudge shows what the others added; each person says *I’d love to* or *Another time* without seeing the others’ answers first; when you both (or most of a group) say yes, it’s a **match**, and *Plan it together* turns it into a shared plan.

```mermaid
flowchart LR
    A["<b>Add</b><br/>to a shared space"]
    Y["<b>Say yes</b><br/>everyone on their own"]
    X["<b>It’s a match</b><br/>you both want this"]
    T["<b>Plan together</b><br/>find a day, who’s in,<br/>who sorts out what"]
    D(["the day"])

    A --> Y
    Y -- "both / most say yes" --> X
    Y -. "another time" .-> A
    X -- "Plan it together" --> T
    T --> D
    D -- "planned before" --> A

    classDef step fill:#FFFEFA,stroke:#E0DDCC,color:#24251E
    classDef key fill:#FFEAD1,stroke:#F57908,color:#24251E
    classDef us fill:#F0EBFA,stroke:#7560C0,color:#24251E
    class A,Y step
    class T key
    class X,D us
```

## Done

- **Accounts:** sign up and sign in with a username and password; each account sees only its own data.
- **Manual memories (backend and a first UI):** save with just a title (description, category, tags, notes, location, exact original text), browse newest first, filter by category, open, edit, delete.
- **Design:** the clickable target design ([oh-app.html](design/oh-app.html)), including couples and groups.

## Where we are (2026-10-15)

- **Built:** accounts and manual memories (backend and a first Flutter UI, still the old look).
- **Designed:** the complete target, including couples and groups ([oh-app.html](design/oh-app.html)); this roadmap and the [decisions](decisions.md) match it.
- **Next:** 010 (the oh! look in the real app), then 011–013. Start a task by asking for it in chat; security-relevant tasks need the owner’s explicit OK first.
- **Decision point:** after 018 and a test with 3–4 couples (see the [vision](vision.md) for the four numbers).

## Plan

Phases in order. Each task is small enough to try on the same day; the order inside a phase can change. Tasks use the short format at the end.

### Phase 1: the oh! app with today’s data (no AI)

### 010 — The oh! look
Goal: the real app looks and reads like the design.
Done when:
- theme (colors light and dark, Nunito, shapes, companion) and the three-tab shell (A little nudge, Planned, My memory) with the header and “Remember this”
- sign-in, Remember and the memory note page use the oh! layout and voice
- existing features keep working

Not now: new data, suggestions, plans.
Security-relevant: no.

### 011 — Richer memories
Goal: save the details that power the other pages.
Done when:
- a memory can carry kind (the design’s list), “good for” moods, who told you, your tags, a link and event dates (from, until)
- Remember asks for them as optional one-tap chips; only the title is required
- My memory: search covers title, note, person, place, link title and tags; browse rows by kind, person, mood and tag; shelves New, Still on your mind, Long forgotten
- every memory belongs to a space; for now each account has only its own *Just me* space, so 015 can add shared spaces without moving data

Not now: link fetching, AI, sharing.
Security-relevant: yes (schema change) → review before merge.

### 012 — A little nudge (rules)
Goal: the first page brings back the right memory for today or the next days.
Done when:
- a deck of every memory that fits (doable soon, not planned, no own dates, no multi-day trips), longest-waiting first, each with why; drag right for *Let’s do it*, left for *Another time*, with the same two buttons under the card
- *Another time* hides a memory for a few days (stored, so it holds across devices)
- one line for the most urgent thing (a plan in the next 3 days, else an event ending or starting within a week); a “Not this? Browse your memory” link

Not now: AI ranking.
Security-relevant: no.

### 013 — Plans
Goal: turn a memory into a concrete plan.
Done when:
- *Let’s do it* picks a day (tonight, tomorrow, this weekend, pick a day) and opens the plan page: time, reminder choice, where (open in maps), who’s coming, checklist, what to bring, the memory’s note
- the Planned tab: next up, this week, later, worth planning
- a passed plan becomes a “planned before” line on its memory; one active plan per memory; *Remember & plan it*

Not now: push notifications (reminders show in the app until 014), sharing (015–017).
Security-relevant: yes (new table with ownership) → review before merge.

### Phase 2: together

Sharing needs everyone on their own phone, so it starts with hosting. Regular things (a weekly drink, date night) come last, once matches and plans work.

### 014 — On our phones
Goal: open the app on any phone over HTTPS, install it to the home screen, get reminders.
Done when:
- hosting approved and running, data private, home-screen install works
- plan reminders arrive as notifications
- account recovery decided and in place before anyone else signs up

Needs owner approval first: hosting, region, cost, recovery method.
Security-relevant: yes → review before merge.

### 015 — Shared spaces
Goal: share a memory with your partner or a group.
Done when:
- start a space (2–8 people) and invite with a link; the invited person signs up or signs in and joins; leave a space; the owner can remove someone or turn the link off
- space tabs under the header on the nudge and My memory (Just me, each space, + New); My memory, the nudge and Remember work per space; each memory shows who added it; Remember is the round + in the header
- after signup: “Who do you do things with?” (my partner, friends or family, just me for now); in *Just me*, the invite card once there are “with someone” memories
- in a shared space Remember says *Suggest to Lena* / *Suggest to the group* (adding is suggesting; there is no separate “propose” feature); *Share with a space* on a Just me memory moves it there (a memory lives in one space)
- the database only shows a space’s memories to its members (tested with a non-member)

Not now: votes, shared plans, news dots.
Security-relevant: yes (membership-based access) → review before merge.

### 016 — Say yes together
Goal: find out what you all want to do, without “I don’t know, what do you want?”.
Done when:
- in a shared space the deck holds three kinds of cards, each labelled: *Lena’s idea* (to answer), *don’t miss it* (an event starting or ending soon) and *you both want this* (a match that fits now, with *Plan it together*); *I’d love to* (right) / *Another time* (left); others’ answers stay hidden until you answer
- *Another time* is never a hard no: it comes back after a few weeks, or sooner, warmly (“Back again: Lena still loves this”); after the third time only you are asked “Keep for someday, or hide it for me?”, and hiding can be undone
- a match (both of a couple; in a group, enough people for the idea: 2 unless it says 4+ or 6+) opens “It’s a match!”; one line on the nudge (“1 match · 3 waiting for Lena”) opens the list; matches also show in Planned
- news counts on the space tabs (“Lena added 2 things”), cleared when you open the space

Not now: notifications for news (later, with 014’s notifications).
Security-relevant: yes (shared rows) → review before merge.

### 017 — Plan together
Goal: plan a date or a trip together.
Done when:
- a plan starts with *Plan it together* (from a match, the match list or any memory); a plan in a shared space is shared: in a group everyone answers *I’m in / Maybe / Can’t*; for a couple the page is lighter (the partner’s “Works for me”, no who’s-in list)
- ideas marked *needs booking* get the to-do “Book it” when planned
- *Let everyone pick*: three suggested days, everyone taps what works, someone picks the best one
- things to sort out can be given to a person; short notes on the plan (no chat; a button opens your own group chat); trips have a day-by-day list
- an invite link for people without the app: a plan card with *I’m in / Maybe / Can’t*, no account needed, can be turned off

Not now: costs per person, in-app chat.
Security-relevant: yes (shared plans, public link) → review before merge.

### 018 — Every week: standing plans and date night
Goal: the things you do regularly organise themselves.
Done when:
- a group can set a standing plan (“Weekly drinks, every Friday 20:00, at …, on from 3 people”); on the day the app asks everyone (“Weekly drinks tonight. In?”), answering is optional and only the *in*s count; at a set time it says “It’s on!” or “Skipped this week” to those who are in
- on its day the standing plan is the top card of that space’s first page (*I’m in* / *Not tonight*), with an *Ask in WhatsApp* link for people without the app; Planned lists it under *Every week*
- a couple can set a date day; the day before, the first page shows three suggestions (matches first); you both pick one; the same pick is planned, different picks show both with *Go with Lena’s / Go with mine*

Needs: notifications from 014.
Not now: rotating hosts, costs, chat.
Security-relevant: yes (scheduled notifications, shared rows) → review before merge.

### Phase 3: less typing, better finding (first AI)

### 019 — Save from a link
Goal: paste a link and most fields fill themselves.
Done when:
- the server fetches the page safely (no local or private addresses, size and time limits) and reads title, site, description, image and, where the page states them, event dates
- kind is suggested from the site type (maps → place, film sites → film, ticket sites → event); you confirm
- if fetching fails you still save by hand; the original link is kept

Not now: AI, screenshots.
Security-relevant: yes (fetching untrusted URLs) → review before merge.

### 020 — “Fill it in for me” (AI step 1)
Goal: AI suggests kind, “good for”, tags and dates from the link text and your note.
Done when:
- suggestions appear as pre-selected chips with “Filled in from the link. Check it?”; nothing is saved without your Save
- only that one memory’s text is sent; it works without AI (feature off or provider down)

Needs owner approval first: provider and model, what is sent, monthly budget.
Security-relevant: yes → review before merge.

### 021 — Ask your memory (AI step 2)
Goal: find something when you don’t remember the words (“that restaurant Lena mentioned”).
Done when:
- a question returns up to three memories from the current space with a short answer in oh!’s voice; it never mentions anything that isn’t saved there
- retrieval runs only over rows you can see (database search first, embeddings if needed); the answer cites the memories it used

Needs owner approval first (as 020).
Security-relevant: yes → review before merge.

### Phase 4: more ways in

### 022 — Save from a screenshot
Goal: keep a screenshot as the memory’s source and let AI read it.
Done when: private image storage that follows the memory’s space, the image shows on the memory, deleting the memory deletes the image, AI suggests fields from it (as 020).
Security-relevant: yes (private file storage) → review before merge.

### 023 — Smarter nudge (optional AI step 3)
Goal: better order and wording of suggestions once there is real usage (what you planned, what you skipped, what matched).
Done when: a measurable improvement over the rules from 012 on your own data; the rules remain the fallback.

### Later, only if needed
- **Costs per person** on a trip plan.
- **Save from the phone’s share sheet** (needs an installed app).
- **In-app chat:** not planned; only if testers ask for it after 018. Group conversation stays in WhatsApp or Signal (the plan has short notes and a link to the group chat).

## When AI comes in, and why

- **Not before phase 3.** The app must be useful without AI: rules can pick suggestions because you gave the details when saving. Without good data AI has nothing to work with, and every call costs money and privacy.
- **First where it removes typing (020).** Saving has to be fast or nobody saves; AI turns a pasted link or a rough note into filled-in chips. One short call per save, you confirm, nothing else is sent.
- **Second where words fail (021).** Search needs you to remember the words; asking in your own words fixes that. It only works over your own memories and must cite them, never invent.
- **Suggestions stay rule-based at first (012).** Rules are explainable (“ends in 3 days”, “on your mind for 7 weeks”) and free. AI can improve the order and wording later (023) once there is usage to learn from.
- **Why together comes before AI:** sharing is the reason people bring others in and the clearest reason to pay; AI only makes saving and finding easier. Rules still pick suggestions in shared spaces; matches come from people, not from a model.
- **Rules for every AI feature:** owner approves provider, model and budget first; calls run on the server, never in the app; only the minimum text is sent, nothing about the account or the other members; no content in logs; the app keeps working when AI is off or down.

## Task format

```text
## NNN — <what I can do afterwards>
Goal: one sentence.
Done when:
- 2–4 things I can check myself
Not now: what is deliberately left out
Security-relevant: yes/no (yes → review before merge)
```

Implementation: simplest design that meets “Done when”, about 3–5 tests (main path, one failure, ownership for a new table or route), `make check`, and a few lines on how to try it. The UI follows the [target design](design/oh-app.html); deviations need the owner’s OK.
