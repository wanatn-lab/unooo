# UNO Table

An online UNO game. Phase 1 (this version) covers the room system only:
create a room, get a shareable link, and have others join via that link.
There is no card game yet — see `PROGRESS.md` for what's built and what's
next.

The UI uses a dark neon "404: Afterparty Not Found" theme (animated club
backdrop, glass panels, glowing accents, avatar art in the player list).
Everything respects `prefers-reduced-motion`, and there's a manual
**Reduce motion** button in the top bar for anyone who wants the animation
off regardless of their system setting.

## Project structure

```
/PROJECT.md         ← working rules for whoever (human or AI) picks up this project
/PROGRESS.md         ← current status, updated at the end of every phase
/backups/            ← DB/config backups, one per phase close
/frontend/           ← the whole app: plain HTML/CSS/JS, no build step
/backend/            ← Supabase schema + why it's built that way
```

## Running it on a fresh machine

No installs, no build step. This is plain HTML/CSS/JS.

1. Get the code: `git clone https://github.com/wanatn-lab/unooo.git`
2. Open a terminal in the `frontend/` folder and start any static file
   server, for example:
   ```
   cd frontend
   npx serve .
   ```
   (or Python's `python3 -m http.server`, or the VS Code "Live Server"
   extension — anything that serves static files works.)
3. Open the URL it gives you (e.g. `http://localhost:3000`) in a browser.

The app already talks to a live Supabase project (see `backend/README.md`)
— there is nothing else to configure to try it locally.

## Deploying

This is a static site, so any static host works (Netlify, GitHub Pages,
Vercel, etc). One thing to set up on whichever host you pick: shareable
links look like `<site>/room/ABC123`, so the host needs to serve
`frontend/index.html` for that path too, not a 404.

- **Netlify**: already handled — `frontend/_redirects` does this automatically.
- **GitHub Pages**: already handled — `frontend/404.html` (a copy of
  `index.html`) is GitHub Pages' standard way of doing this, since Pages
  has no rewrite rules of its own.
- **Other hosts**: add an equivalent rewrite rule for `/room/*` →
  `index.html`, or share links as `<site>/?code=ABC123` instead (the app
  supports both).

## Testing the room flow

1. Open the site, enter a name, click **Create Room**.
2. Copy the invite link shown in the lobby.
3. Open that link in 2–3 other browsers/incognito windows, each with a
   different name, and click **Join Room**.
4. All players should appear in every window's lobby list within a couple
   of seconds, with no refresh needed.
5. Opening a made-up room code, or a 9th player joining a full room, should
   show a clear error — never a blank or stuck screen.
