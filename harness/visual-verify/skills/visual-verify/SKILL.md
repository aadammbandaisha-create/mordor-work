---
name: visual-verify
description: verify web UI changes by driving a real browser and reading screenshots; trigger on /visual-verify, "see what you built", "screenshot the app", "verify the UI visually", "does it look right"
---

# visual-verify

Drive a real browser via the project-local Playwright CLI, capture
screenshots, read them with multimodal vision, and iterate until the UI
matches the intent. Uses the CLI rather than the Playwright MCP to avoid
the ~4x token overhead of streaming accessibility trees.

## When NOT to use

- The project has no web UI (CLI tools, libraries, services with no frontend).
- The change is pure logic, data processing, or backend -- no visual surface.
- You only need to confirm tests pass; use the test runner directly.
- The user explicitly asked to run tests, not to verify appearance.

---

## Step 1 -- Availability check

Run this command inside the project directory:

```
npx --no-install playwright --version
```

If the command fails (exit non-zero or "not found"):

- Tell the user Playwright is not installed locally.
- Give the exact install commands:

  ```
  npm install --save-dev playwright
  npx playwright install chromium
  ```

  Note: `npx playwright install chromium` downloads ~130 MB. Ask for
  explicit approval before proceeding -- never install unprompted.

- STOP and wait for the user to confirm install is complete before
  continuing.

---

## Step 2 -- Determine the target URL

Try these sources in order; stop at the first one that works:

1. The user stated a URL or port in the current message -- use it.
2. The project's `package.json` has a `start` or `dev` script -- launch it
   in the background (e.g. via the Bash tool with `run_in_background: true`),
   then poll the port (try `curl -s -o /dev/null -w "%{http_code}"
   http://localhost:<PORT>` every 2 s, up to 20 s) until it responds.
   Record the PID or process so you can stop it in Step 5.
3. The project has a `vite.config.*`, `next.config.*`, `nuxt.config.*`, or
   similar -- infer the default port (Vite: 5173, Next: 3000, Nuxt: 3000,
   CRA: 3000).
4. Ask the user: "What URL or port should I navigate to?"

---

## Step 3 -- Screenshot loop

### 3a. Write a one-off driver script

Save the script at `.claude/screenshots/_drive.js` (create the directory
if absent). Overwrite on each iteration. Template:

```js
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();

  // Capture console messages and page errors
  const logs = [];
  page.on('console', msg => logs.push('[console.' + msg.type() + '] ' + msg.text()));
  page.on('pageerror', err => logs.push('[pageerror] ' + err.message));

  // --- desktop viewport ---
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('TARGET_URL', { waitUntil: 'networkidle' });
  // Optional: add interactions here (page.click, page.fill, etc.)
  await page.screenshot({ path: '.claude/screenshots/STEP_NAME.png', fullPage: true });

  // --- mobile viewport (add when mobile layout is relevant) ---
  // await page.setViewportSize({ width: 390, height: 844 });
  // await page.goto('TARGET_URL', { waitUntil: 'networkidle' });
  // await page.screenshot({ path: '.claude/screenshots/STEP_NAME-mobile.png', fullPage: true });

  await browser.close();

  if (logs.length) {
    console.log('--- browser logs ---');
    logs.forEach(l => console.log(l));
  } else {
    console.log('no browser console output');
  }
})();
```

Replace `TARGET_URL` and `STEP_NAME` with the actual URL and a short
descriptive name (e.g. `homepage`, `after-login`, `modal-open`).

Customise interactions to exercise the specific UI change under review.

### 3b. Run the script

```
node .claude/screenshots/_drive.js
```

Capture stdout (the browser log output).

### 3c. Read the screenshot

Use the Read tool on the `.png` file. Claude Code is multimodal -- the
image will be rendered for inspection.

### 3d. Evaluate

Check BOTH of these:

- **Visual**: does the UI match the intended change? Look for layout
  breaks, missing elements, wrong styles, truncated text, overlapping
  components.
- **Console**: are there errors in the captured browser log? A visually
  clean screenshot with `[pageerror]` or `[console.error]` lines is NOT
  a pass.

### 3e. Iterate if needed

If evaluation fails:

- Fix the code defect (or add an interaction step to reach the right
  state).
- Increment the step name (e.g. `homepage-v2.png`) so each attempt is
  preserved.
- Re-run from 3b.

Limit to 5 iterations without user input; if still failing, report the
current screenshot and the console output and ask the user for guidance.

---

## Step 4 -- Mobile check (when relevant)

Add a second viewport block (390x844) to the driver script when:
- The change touches responsive layout, media queries, or mobile-specific
  components.
- The user mentions mobile or small screen.

Label the file `<step>-mobile.png`.

---

## Step 5 -- Wrap-up

1. Report what was verified: list each screenshot file read, what was
   checked, and the pass/fail verdict.
2. If you launched a dev server in Step 2, stop it now (kill the
   background process by PID).
3. Note that `.claude/screenshots/` should be gitignored. If the project
   has a `.gitignore` and the directory is not already listed, offer to
   add it:

   ```
   .claude/screenshots/
   ```

   Wait for the user to say yes before modifying `.gitignore`.
