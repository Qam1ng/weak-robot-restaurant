/* eslint-disable require-jsdoc, max-len */
const {setGlobalOptions} = require("firebase-functions/v2");
const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

admin.initializeApp();

const db = getFirestore();
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const DEFAULT_MODEL = "gpt-4o-mini";
const DEFAULT_TEMPERATURE = 0.4;
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

setGlobalOptions({
  maxInstances: 10,
  region: "us-central1",
});

function applyCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set(
      "Access-Control-Allow-Headers",
      "Content-Type, Authorization",
  );
}

function handleOptions(req, res) {
  applyCors(res);
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

function requirePost(req, res) {
  if (req.method !== "POST") {
    res.status(405).json({error: "method_not_allowed"});
    return false;
  }
  return true;
}

function parseBody(req) {
  if (req.body == null) {
    return {};
  }
  if (typeof req.body === "string") {
    try {
      return JSON.parse(req.body);
    } catch (_err) {
      return null;
    }
  }
  return req.body;
}

function sanitizeText(value, fallback = "") {
  return String(value == null ? fallback : value).trim();
}

function asNumber(value, fallback) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function buildDialoguePrompts(body) {
  const fallback = sanitizeText(body.fallback, "Okay.");
  const kind = sanitizeText(body.kind, "directed_utterance");
  const model = sanitizeText(body.model, DEFAULT_MODEL) || DEFAULT_MODEL;
  const temperature = asNumber(body.temperature, DEFAULT_TEMPERATURE);

  if (kind === "help_utterance") {
    const strategy = sanitizeText(body.strategy, "");
    const urgency = sanitizeText(body.urgency, "medium");
    const escalation = asNumber(body.escalation, 0);
    const mbti = sanitizeText(body.mbti, "");
    const item = sanitizeText(body.item, "item");
    const requestType = sanitizeText(body.request_type, "HANDOFF");

    return {
      model,
      temperature,
      fallback,
      systemPrompt: "Write one short in-game delegation line from robot to player. Keep it natural, concrete, polite, and under 18 words. No quotes. No options.",
      userPrompt: [
        `request_type=${requestType}`,
        `strategy=${strategy}`,
        `urgency=${urgency}`,
        `escalation=${escalation}`,
        `mbti=${mbti}`,
        `item=${item}`,
        `fallback=${fallback}`,
      ].join(" "),
    };
  }

  const sourceRole = sanitizeText(body.source_role, "player");
  const recipientRole = sanitizeText(body.recipient_role, "robot");
  const intentType = sanitizeText(body.intent_type, "directed_reply");
  const itemName = sanitizeText(body.item_name, "");
  const contextNote = sanitizeText(body.context_note, "");

  return {
    model,
    temperature,
    fallback,
    systemPrompt: "Write one short in-game line of direct speech. Keep it natural, concrete, polite, and under 18 words. No quotes. No stage directions.",
    userPrompt: [
      `speaker=${sourceRole}`,
      `recipient=${recipientRole}`,
      `intent=${intentType}`,
      `item=${itemName}`,
      `context=${contextNote}`,
      `fallback=${fallback}`,
    ].join(" "),
  };
}

async function requestOpenAI(dialogueRequest) {
  const apiKey = sanitizeText(OPENAI_API_KEY.value(), "");
  if (apiKey === "") {
    return {
      utterance: dialogueRequest.fallback,
      meta: {
        provider: "fallback",
        status: "missing_key",
        fallback: dialogueRequest.fallback,
      },
    };
  }

  const response = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer " + apiKey,
    },
    body: JSON.stringify({
      model: dialogueRequest.model,
      messages: [
        {role: "system", content: dialogueRequest.systemPrompt},
        {role: "user", content: dialogueRequest.userPrompt},
      ],
      temperature: dialogueRequest.temperature,
      max_tokens: 60,
    }),
  });

  if (!response.ok) {
    return {
      utterance: dialogueRequest.fallback,
      meta: {
        provider: "fallback",
        status: "http_error",
        http_code: response.status,
        fallback: dialogueRequest.fallback,
      },
    };
  }

  const payload = await response.json();
  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  const firstChoice = choices.length > 0 ? choices[0] : {};
  const message = firstChoice && typeof firstChoice === "object" ?
    firstChoice.message || {} : {};
  const content = sanitizeText(
      message && typeof message === "object" ? message.content : "",
      "",
  ).replace(/\n+/g, " ");

  if (content === "") {
    return {
      utterance: dialogueRequest.fallback,
      meta: {
        provider: "fallback",
        status: "empty_content",
        fallback: dialogueRequest.fallback,
      },
    };
  }

  return {
    utterance: content,
    meta: {
      provider: "openai",
      status: "ok",
      model: dialogueRequest.model,
    },
  };
}

exports.apiDialogue = onRequest({secrets: [OPENAI_API_KEY]}, async (req, res) => {
  applyCors(res);
  if (handleOptions(req, res)) {
    return;
  }
  if (!requirePost(req, res)) {
    return;
  }

  const body = parseBody(req);
  if (body == null || typeof body !== "object") {
    res.status(400).json({error: "invalid_json_body"});
    return;
  }

  const requestId = sanitizeText(body.request_id, "");
  const kind = sanitizeText(body.kind, "directed_utterance");
  const fallback = sanitizeText(body.fallback, "Okay.");

  try {
    const dialogueRequest = buildDialoguePrompts(body);
    const result = await requestOpenAI(dialogueRequest);

    res.status(200).json({
      request_id: requestId,
      kind,
      utterance: result.utterance,
      meta: result.meta,
      fallback,
    });
  } catch (err) {
    logger.error("apiDialogue failed", err);
    res.status(200).json({
      request_id: requestId,
      kind,
      utterance: fallback,
      meta: {
        provider: "fallback",
        status: "exception",
        fallback,
      },
      fallback,
    });
  }
});

exports.apiLog = onRequest(async (req, res) => {
  applyCors(res);
  if (handleOptions(req, res)) {
    return;
  }
  if (!requirePost(req, res)) {
    return;
  }

  const body = parseBody(req);
  if (body == null || typeof body !== "object") {
    res.status(400).json({error: "invalid_json_body"});
    return;
  }

  const sessionId = sanitizeText(body.session_id, "");
  const eventType = sanitizeText(body.type, "");
  const payload = typeof body.payload === "object" && body.payload !== null ?
    body.payload : {};
  const clientTs = asNumber(body.ts, Date.now());

  if (sessionId === "" || eventType === "") {
    res.status(400).json({error: "missing_session_or_type"});
    return;
  }

  const sessionRef = db.collection("sessions").doc(sessionId);
  const eventRef = sessionRef.collection("events").doc();

  try {
    const sessionSnapshot = await sessionRef.get();
    const sessionData = {
      session_id: sessionId,
      build_version: sanitizeText(body.build_version, ""),
      platform: sanitizeText(body.platform, "web"),
      user_agent: sanitizeText(body.user_agent, ""),
      updated_at: FieldValue.serverTimestamp(),
      last_event_type: eventType,
      last_client_ts: clientTs,
    };
    if (!sessionSnapshot.exists) {
      sessionData.created_at = FieldValue.serverTimestamp();
    }
    await sessionRef.set(sessionData, {merge: true});

    await eventRef.set({
      type: eventType,
      ts: clientTs,
      payload,
      created_at: FieldValue.serverTimestamp(),
    });

    res.status(200).json({
      ok: true,
      session_id: sessionId,
      event_id: eventRef.id,
    });
  } catch (err) {
    logger.error("apiLog failed", err);
    res.status(500).json({error: "log_write_failed"});
  }
});
