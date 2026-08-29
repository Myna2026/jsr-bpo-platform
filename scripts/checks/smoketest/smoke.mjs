// Smoke-Test: meldet sich mit dem Claude-Test-Zugang an, klickt durch ALLE sichtbaren Menuepunkte
// und prueft, dass keine Ansicht abstuerzt (kein uncaught Error) und jede etwas rendert.
// Bewusst NUR Navigation, KEINE Aktions-Knoepfe (Speichern/Loeschen) — der Zugang schreibt sonst in die Live-DB.
//
// Aufruf:   node smoke.mjs            (Ziel-URL aus SMOKE_URL, Standard http://localhost:8799/hr.html)
// Exit 0 = alles gut · Exit 1 = eine Ansicht ist abgestuerzt · Exit 2 = Test konnte nicht laufen (Browser fehlt) -> Warnung, kein Block.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
function creds() {
  let c = {};
  try { c = JSON.parse(readFileSync(join(HERE, ".smoke-credentials.json"), "utf8")); } catch (_e) {}
  return {
    url: process.env.SMOKE_URL || c.baseUrl || "http://localhost:8799/hr.html",
    email: process.env.SMOKE_EMAIL || c.email || "claudetest@25hrs.net",
    password: process.env.SMOKE_PW || c.password || "",
  };
}

let chromium;
try { ({ chromium } = await import("playwright")); }
catch (_e) { console.log("smoketest: playwright nicht installiert -> uebersprungen (kein Block)."); process.exit(2); }

const { url, email, password } = creds();
if (!password) { console.log("smoketest: kein Passwort (SMOKE_PW / .smoke-credentials.json) -> uebersprungen."); process.exit(2); }

let browser;
try { browser = await chromium.launch({ channel: "chrome", headless: true }); }
catch (e) {
  try { browser = await chromium.launch({ headless: true }); }
  catch (_e2) { console.log("smoketest: kein Browser startbar (" + (e.message || "") + ") -> uebersprungen (kein Block)."); process.exit(2); }
}

const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
const pageErrors = [];
page.on("pageerror", (err) => pageErrors.push(String(err && err.message || err)));

const fail = async (msg) => {
  try { await page.screenshot({ path: join(HERE, "smoke-fail.png"), fullPage: false }); } catch (_e) {}
  console.log("\n✗ SMOKE FEHLGESCHLAGEN: " + msg);
  await browser.close();
  process.exit(1);
};

try {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });

  // Login: E-Mail, auf Passwort-Modus umschalten, Passwort, Anmelden.
  await page.locator("input.lc-inp[type=email]").first().fill(email, { timeout: 20000 });
  await page.getByText("Stattdessen mit Passwort einloggen").click({ timeout: 10000 });
  await page.locator("input.lc-inp[type=password]").first().fill(password);
  await page.getByRole("button", { name: "Anmelden" }).click();

  // Warten, bis die Menueleiste geladen ist (auth-gated loads koennen ein paar Sekunden brauchen).
  await page.waitForSelector(".sidebar .ni", { timeout: 30000 }).catch(() => {});
  const niCount = await page.locator(".sidebar .ni").count();
  if (!niCount) await fail("nach dem Anmelden erscheint kein Menue (Login fehlgeschlagen oder Absturz beim Start). pageErrors: " + JSON.stringify(pageErrors.slice(0, 3)));
  if (pageErrors.length) await fail("Fehler direkt nach dem Start: " + pageErrors[0]);

  // Alle einklappbaren Sektionen oeffnen, damit alle Menuepunkte im DOM sind.
  await page.evaluate(() => {
    for (const s of document.querySelectorAll(".sidebar .nav-section")) {
      let el = s.nextElementSibling, hasNi = false;
      while (el && !el.classList.contains("nav-section")) { if (el.classList && el.classList.contains("ni")) { hasNi = true; break; } el = el.nextElementSibling; }
      if (!hasNi) s.click();
    }
  });
  await page.waitForTimeout(400);

  // Menuepunkte einsammeln (Label + Index) und der Reihe nach anklicken.
  const labels = await page.locator(".sidebar .ni .ni-label").allInnerTexts();
  console.log("smoketest: " + labels.length + " Menuepunkte gefunden. Ziel: " + url);
  const results = [], crashed = [], blank = [], dead = [];
  for (let i = 0; i < labels.length; i++) {
    const label = (labels[i] || "").trim();
    const before = pageErrors.length;
    const item = page.locator(".sidebar .ni").nth(i);
    try { await item.click({ timeout: 10000 }); }
    catch (e) { dead.push(label + " (Klick: " + (e.message || "").split("\n")[0] + ")"); continue; }
    // Auf echten Inhalt warten (bis ~2,5s), damit langsame Ansichten kein Fehlalarm sind.
    // .content enthaelt immer DialogHost/AgentInsights/Mobile-FAB -> die zaehlen wir NICHT als Inhalt:
    // gemessen wird sichtbarer Text ausserhalb dieser Fixbausteine.
    const filled = await page.waitForFunction(() => {
      const c = document.querySelector(".content"); if (!c) return false;
      let t = 0;
      for (const el of c.children) {
        if (el.matches(".mobile-fab-area")) continue;
        t += (el.innerText || "").trim().length;
      }
      return t > 3;
    }, { timeout: 2500 }).then(() => true).catch(() => false);

    // 1) kein neuer uncaught Error
    const threw = pageErrors.length > before ? pageErrors[pageErrors.length - 1] : null;
    // 2) der Punkt ist aktiv geworden (Klick hat reagiert)
    const active = await item.evaluate((el) => el.classList.contains("active")).catch(() => false);

    if (threw) crashed.push(label + " -> " + threw);
    else if (!filled) blank.push(label);
    else if (!active) dead.push(label + " (Klick ohne Wirkung)");
    else results.push("✓ " + label);
  }

  console.log("\n" + results.join("   "));
  const problems = [];
  if (crashed.length) problems.push("ABGESTUERZT (" + crashed.length + "):\n  - " + crashed.join("\n  - "));
  if (blank.length)   problems.push("LEERE ANSICHT (" + blank.length + "):\n  - " + blank.join("\n  - "));
  if (dead.length)    problems.push("KNOPF REAGIERT NICHT (" + dead.length + "):\n  - " + dead.join("\n  - "));
  if (problems.length) {
    console.log("\n✗ SMOKE FEHLGESCHLAGEN:\n" + problems.join("\n"));
    try { await page.screenshot({ path: join(HERE, "smoke-fail.png") }); } catch (_e) {}
    await browser.close();
    process.exit(1);
  }
  console.log("\n✓ SMOKE OK: " + labels.length + " Ansichten geladen, kein Absturz, Navigation reagiert.");
  await browser.close();
  process.exit(0);
} catch (e) {
  await fail("unerwartet: " + (e && e.stack || e));
}
