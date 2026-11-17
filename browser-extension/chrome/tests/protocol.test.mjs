import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import test from "node:test";

import {
  PCMProtocolSession,
  float32ToPCM16Base64,
  isAllowedMeetURL,
  normalizeFloatSample,
} from "../protocol.js";

const manifest = JSON.parse(fs.readFileSync(new URL("../manifest.json", import.meta.url)));

test("manifest has a stable allowlistable id and only required capture permissions", () => {
  const digest = crypto.createHash("sha256")
    .update(Buffer.from(manifest.key, "base64"))
    .digest()
    .subarray(0, 16)
    .toString("hex");
  const extensionId = [...digest]
    .map((character) => "abcdefghijklmnop"[Number.parseInt(character, 16)])
    .join("");

  assert.equal(extensionId, "cdoilhpndmdimjbnagfgldhkjojjjjha");
  assert.deepEqual(
    manifest.permissions.toSorted(),
    ["activeTab", "nativeMessaging", "offscreen", "tabCapture"].toSorted(),
  );
  assert.equal(manifest.host_permissions, undefined);
  assert.equal(manifest.background.type, "module");
  assert.equal(manifest.action.default_popup, "popup.html");
  for (const iconPath of Object.values(manifest.icons)) {
    assert.equal(fs.existsSync(new URL(`../${iconPath}`, import.meta.url)), true);
  }
});

test("popup provides prominent disclosure before the user starts audio capture", () => {
  const popup = fs.readFileSync(new URL("../popup.html", import.meta.url), "utf8");
  const popupStyles = fs.readFileSync(new URL("../popup.css", import.meta.url), "utf8");
  assert.match(popup, /Yalnız o anda açık olan/);
  assert.match(popup, /Diğer sekmeler okunmaz veya\s+kaydedilmez/);
  assert.match(popup, /ElevenLabs Scribe v2/);
  assert.match(popup, /işlenmesini onaylarsınız/);
  assert.match(popup, /id="capture-button"/);
  assert.doesNotMatch(popup, /<script(?![^>]*\bsrc=)/);
  assert.match(popupStyles, /--surface:\s*#121212/);
  assert.match(popupStyles, /--danger:\s*#fe4b4b/);
  assert.match(popupStyles, /--cyan:\s*#14d4ff/);
  assert.match(popupStyles, /border-radius:\s*22px/);
  for (const assetName of ["figma-stop", "figma-video", "figma-voice", "figma-warning"]) {
    assert.equal(
      fs.existsSync(new URL(`../images/${assetName}.svg`, import.meta.url)),
      true,
    );
  }
});

test("only canonical Google Meet call URLs are allowed", () => {
  assert.equal(isAllowedMeetURL("https://meet.google.com/abc-defg-hij"), true);
  assert.equal(isAllowedMeetURL("https://meet.google.com/lookup/team_room"), true);
  assert.equal(isAllowedMeetURL("https://meet.google.com/"), false);
  assert.equal(isAllowedMeetURL("https://meet.google.com.evil.test/abc-defg-hij"), false);
  assert.equal(isAllowedMeetURL("http://meet.google.com/abc-defg-hij"), false);
});

test("PCM conversion clamps samples and writes little-endian int16", () => {
  const encoded = float32ToPCM16Base64(new Float32Array([-2, -1, 0, 1, 2]));
  const bytes = Buffer.from(encoded, "base64");
  assert.deepEqual(
    Array.from({ length: 5 }, (_, index) => bytes.readInt16LE(index * 2)),
    [-32768, -32768, 0, 32767, 32767],
  );
  assert.equal(normalizeFloatSample(Number.NaN), 0);
});

test("protocol sequence and acknowledgement enforce bounded backpressure", () => {
  const session = new PCMProtocolSession("12345678-1234-1234-1234-123456789abc", 2);
  const samples = new Float32Array([0.1, -0.1]);
  assert.equal(session.makeAudioMessage(samples, 48_000, 1).sequence, 0);
  assert.equal(session.makeAudioMessage(samples, 48_000, 1).sequence, 1);
  assert.throws(() => session.makeAudioMessage(samples, 48_000, 1), /backpressure/);
  assert.throws(() => session.acknowledge(1), /acknowledgement/);
  session.acknowledge(0);
  assert.equal(session.makeAudioMessage(samples, 48_000, 1).sequence, 2);
  assert.throws(() => session.acknowledge(8), /acknowledgement/);
});

test("protocol rejects invalid audio layouts before native messaging", () => {
  const session = new PCMProtocolSession("12345678-1234-1234-1234-123456789abc");
  assert.throws(() => session.makeAudioMessage(new Float32Array(), 48_000, 1), /layout/);
  assert.throws(
    () => session.makeAudioMessage(new Float32Array([0, 0, 0]), 48_000, 2),
    /layout/,
  );
  assert.throws(
    () => session.makeAudioMessage(new Float32Array([0]), 1_000, 1),
    /sample rate/,
  );
});
