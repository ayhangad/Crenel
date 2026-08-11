export const PROTOCOL_VERSION = 1;
export const NATIVE_HOST_NAME = "com.gad.meetingnotch.browser_audio";
export const MAX_IN_FLIGHT_CHUNKS = 8;

const MEET_CODE_PATH = /^\/[a-z]{3}-[a-z]{4}-[a-z]{3}\/?$/i;
const MEET_LOOKUP_PATH = /^\/lookup\/[a-z0-9_-]+\/?$/i;

export function isAllowedMeetURL(rawURL) {
  try {
    const url = new URL(rawURL);
    return url.protocol === "https:"
      && url.hostname === "meet.google.com"
      && (MEET_CODE_PATH.test(url.pathname) || MEET_LOOKUP_PATH.test(url.pathname));
  } catch {
    return false;
  }
}

export function normalizeFloatSample(sample) {
  if (!Number.isFinite(sample)) return 0;
  return Math.max(-1, Math.min(1, sample));
}

export function float32ToPCM16Base64(samples) {
  if (!(samples instanceof Float32Array)) {
    throw new TypeError("samples must be Float32Array");
  }
  const bytes = new Uint8Array(samples.length * 2);
  const view = new DataView(bytes.buffer);
  for (let index = 0; index < samples.length; index += 1) {
    const normalized = normalizeFloatSample(samples[index]);
    const value = normalized < 0
      ? Math.round(normalized * 32768)
      : Math.round(normalized * 32767);
    view.setInt16(index * 2, value, true);
  }

  let binary = "";
  const blockSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += blockSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + blockSize));
  }
  return btoa(binary);
}

export class PCMProtocolSession {
  constructor(sessionId, maxInFlight = MAX_IN_FLIGHT_CHUNKS) {
    if (typeof sessionId !== "string" || sessionId.length < 16) {
      throw new TypeError("invalid session id");
    }
    this.sessionId = sessionId;
    this.maxInFlight = maxInFlight;
    this.nextSequence = 0;
    this.lastAcknowledgedSequence = -1;
  }

  get inFlightCount() {
    return this.nextSequence - this.lastAcknowledgedSequence - 1;
  }

  acknowledge(sequence) {
    if (!Number.isSafeInteger(sequence)
      || sequence !== this.lastAcknowledgedSequence + 1
      || sequence >= this.nextSequence) {
      throw new RangeError("invalid acknowledgement");
    }
    this.lastAcknowledgedSequence = sequence;
  }

  makeAudioMessage(samples, sampleRate, channels) {
    if (this.inFlightCount >= this.maxInFlight) {
      throw new Error("native bridge backpressure limit exceeded");
    }
    if (!Number.isSafeInteger(sampleRate) || sampleRate < 8_000 || sampleRate > 192_000) {
      throw new RangeError("invalid sample rate");
    }
    if (!Number.isSafeInteger(channels) || channels < 1 || channels > 2) {
      throw new RangeError("invalid channel count");
    }
    if (samples.length === 0 || samples.length % channels !== 0) {
      throw new RangeError("invalid PCM frame layout");
    }

    const message = {
      version: PROTOCOL_VERSION,
      type: "audio",
      sessionId: this.sessionId,
      sequence: this.nextSequence,
      sampleRate,
      channels,
      frameCount: samples.length / channels,
      pcmS16LE: float32ToPCM16Base64(samples),
    };
    this.nextSequence += 1;
    return message;
  }
}
