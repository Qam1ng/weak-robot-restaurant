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
const STRATEGIES = [
  "reciprocity",
  "authority",
  "liking",
  "commitment",
  "social_proof",
  "scarcity",
];
const STRATEGY_SET = new Set(STRATEGIES);
const SESSION_SOURCES = new Set([
  "qualtrics",
  "standalone_test",
  "local_test",
]);
const HANDOFF_MODES = new Set([
  "TAKEOVER_TASK",
  "TAKEOVER_ITEM",
]);
const ASSIGNMENT_MODES = new Set([
  "trial_neutral",
  "session_coverage",
  "condition_weighted",
]);
const ASSIGNMENT_SOURCES = new Set([
  "trial_neutral",
  "backend",
  "local",
  "local_fallback",
]);
const TASK_TERMINAL_STATES = new Set([
  "",
  "completed",
  "failed",
]);
const TASK_STEPS = new Set([
  "",
  "TAKE_ORDER",
  "PICKUP_FROM_KITCHEN",
  "DELIVER_AND_SERVE",
]);

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

function asBoolean(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  return fallback;
}

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function sanitizeAssignmentBuckets(value) {
  const buckets = asObject(value);
  return {
    urgency_bucket: sanitizeText(buckets.urgency_bucket, ""),
    busyness_bucket: sanitizeText(buckets.busyness_bucket, ""),
    player_active_tasks_bucket: sanitizeText(
        buckets.player_active_tasks_bucket,
        "",
    ),
    battery_mode_bucket: sanitizeText(buckets.battery_mode_bucket, ""),
  };
}

function sanitizeTipiResponses(value) {
  const raw = asObject(value);
  const cleaned = {};
  for (let i = 1; i <= 10; i += 1) {
    const rawValue = raw[i] != null ? raw[i] : raw[`tipi_response_${i}`];
    cleaned[`tipi_response_${i}`] = asNumber(rawValue, 4.0);
  }
  return cleaned;
}

function sanitizeTipiScores(value) {
  const raw = asObject(value);
  return {
    trait_O: asNumber(raw.O != null ? raw.O : raw.trait_O, 4.0),
    trait_C: asNumber(raw.C != null ? raw.C : raw.trait_C, 4.0),
    trait_E: asNumber(raw.E != null ? raw.E : raw.trait_E, 4.0),
    trait_A: asNumber(raw.A != null ? raw.A : raw.trait_A, 4.0),
    trait_N: asNumber(raw.N != null ? raw.N : raw.trait_N, 4.0),
  };
}

function sanitizeFiniteNumber(value, fallback = null) {
  if (value == null || value === "") {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

const RUNTIME_DEBUG_EVENT_TYPES = new Set([
  "robot_task_assigned",
  "robot_step_changed",
  "navigation_start",
  "navigation_retry",
  "navigation_failed",
  "pickup_started",
  "pickup_failed",
  "delivery_started",
  "delivery_failed",
]);

const RUNTIME_DEBUG_EVENT_REASONS = new Set([
  "",
  "navigation_retry_exhausted",
  "no_navigation_path",
  "stuck_retry",
  "missing_inventory",
  "inventory_full",
  "item_missing",
  "too_far_from_item",
  "delivery_state_invalid",
  "customer_cannot_receive_item",
  "customer_missing",
]);

const RUNTIME_DEBUG_ROBOT_STEPS = new Set([
  "",
  "TAKE_ORDER",
  "PICKUP_FROM_KITCHEN",
  "DELIVER_AND_SERVE",
]);

const RUNTIME_DEBUG_DELEGATION_SCENARIOS = new Set([
  "",
  "battery_pressure",
  "workload_overload",
  "deadline_pressure",
  "trial_tutorial",
]);

function sanitizeEnumText(value, allowed, fallback = "") {
  const cleaned = sanitizeText(value, fallback);
  return allowed.has(cleaned) ? cleaned : fallback;
}

function assignmentCounterDocId(buckets) {
  return [
    sanitizeText(buckets.urgency_bucket, "medium"),
    sanitizeText(buckets.busyness_bucket, "medium"),
    sanitizeText(buckets.player_active_tasks_bucket, "medium"),
    sanitizeText(buckets.battery_mode_bucket, "normal"),
  ].join("__");
}

function weightedStrategyChoice(counts) {
  let totalWeight = 0.0;
  const weighted = [];
  for (const strategy of STRATEGIES) {
    const count = Math.max(asNumber(counts[strategy], 0), 0);
    const weight = 1.0 / (count + 1.0);
    weighted.push({strategy, weight});
    totalWeight += weight;
  }
  let draw = Math.random() * totalWeight;
  for (const entry of weighted) {
    draw -= entry.weight;
    if (draw <= 0.0) {
      return entry.strategy;
    }
  }
  return STRATEGIES[STRATEGIES.length - 1];
}

async function assignStrategyGlobally(data) {
  const requestId = sanitizeText(data.request_id, "");
  const buckets = sanitizeAssignmentBuckets(data.assignment_buckets);
  const forcedStrategy = sanitizeEnumText(data.forced_strategy, STRATEGY_SET, "");
  const counterId = assignmentCounterDocId(buckets);
  const counterRef = db.collection("assignment_counters").doc(counterId);
  let chosen = STRATEGIES[0];

  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(counterRef);
    const counts = {};
    for (const strategy of STRATEGIES) {
      counts[strategy] = 0;
    }
    if (snapshot.exists) {
      const existing = snapshot.data() || {};
      for (const strategy of STRATEGIES) {
        counts[strategy] = asNumber(existing[strategy], 0);
      }
    }
    chosen = forcedStrategy || weightedStrategyChoice(counts);
    counts[chosen] += 1;
    tx.set(counterRef, {
      urgency_bucket: buckets.urgency_bucket,
      busyness_bucket: buckets.busyness_bucket,
      player_active_tasks_bucket: buckets.player_active_tasks_bucket,
      battery_mode_bucket: buckets.battery_mode_bucket,
      reciprocity: counts.reciprocity,
      authority: counts.authority,
      liking: counts.liking,
      commitment: counts.commitment,
      social_proof: counts.social_proof,
      scarcity: counts.scarcity,
      updated_at: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {
    request_id: requestId,
    strategy: chosen,
    assignment_buckets: buckets,
  };
}

async function upsertParticipantLog(sessionId, platform, buildVersion, data) {
  const participantId = sanitizeText(data.participant_id, sessionId);
  const participantRef = db.collection("participants").doc(participantId);
  const snapshot = await participantRef.get();
  const doc = {
    participant_id: participantId,
    session_id: sanitizeText(data.session_id, sessionId),
    session_source: sanitizeEnumText(
        data.session_source,
        SESSION_SOURCES,
        "standalone_test",
    ),
    qualtrics_id: sanitizeText(data.qualtrics_id, ""),
    experiment_version: sanitizeText(data.experiment_version, ""),
    nickname: sanitizeText(data.nickname, ""),
    platform,
    build_version: buildVersion,
    question_count: asNumber(data.question_count, 0),
    tipi_responses: sanitizeTipiResponses(data.tipi_responses),
    tipi_scores: sanitizeTipiScores(data.tipi_scores),
  };
  if (!snapshot.exists) {
    doc.created_at = FieldValue.serverTimestamp();
  }
  await participantRef.set(doc, {merge: true});
  return {participant_id: participantId};
}

async function upsertHelpRequestLog(sessionId, participantId, data) {
  const requestId = sanitizeText(data.request_id, "");
  if (requestId === "") {
    throw new Error("missing_request_id");
  }
  const loggedSessionId = sanitizeText(data.session_id, sessionId);
  const helpRequestKey = `${encodeURIComponent(loggedSessionId)}__${encodeURIComponent(requestId)}`;
  const requestRef = db.collection("help_requests").doc(helpRequestKey);
  const doc = {
    participant_id: sanitizeText(data.participant_id, participantId),
    session_id: loggedSessionId,
    session_source: sanitizeEnumText(
        data.session_source,
        SESSION_SOURCES,
        "standalone_test",
    ),
    experiment_version: sanitizeText(data.experiment_version, ""),
    episode_id: sanitizeText(data.episode_id, ""),
    request_id: requestId,
    help_request_key: helpRequestKey,
    delegation_scenario: sanitizeText(data.delegation_scenario, ""),
    request_index_in_session: asNumber(data.request_index_in_session, 0),
    display_index_in_session: asNumber(data.display_index_in_session, 0),
    status: sanitizeText(data.status, ""),
    created_at_ms: asNumber(data.created_at_ms, 0),
    prompted_at_ms: asNumber(data.prompted_at_ms, -1),
    task_id: sanitizeText(data.task_id, ""),
    item_needed: sanitizeText(data.item_needed, ""),
    handoff_mode: sanitizeEnumText(data.handoff_mode, HANDOFF_MODES, ""),
    slack_ms: asNumber(data.slack_ms, 0),
    phase_name: sanitizeText(data.phase_name, ""),
    busyness: asNumber(data.busyness, 0.0),
    urgency: asNumber(data.urgency, 0.0),
    player_active_tasks: asNumber(data.player_active_tasks, 0),
    battery_level: asNumber(data.battery_level, 0.0),
    prompt_slack_ms: asNumber(data.prompt_slack_ms, -1),
    prompt_phase_name: sanitizeText(data.prompt_phase_name, ""),
    prompt_busyness: asNumber(data.prompt_busyness, -1.0),
    prompt_player_active_tasks: asNumber(data.prompt_player_active_tasks, -1),
    prompt_battery_level: asNumber(data.prompt_battery_level, -1.0),
    prompt_task_step: sanitizeEnumText(data.prompt_task_step, TASK_STEPS, ""),
    trait_O: asNumber(data.trait_O, 0.0),
    trait_C: asNumber(data.trait_C, 0.0),
    trait_E: asNumber(data.trait_E, 0.0),
    trait_A: asNumber(data.trait_A, 0.0),
    trait_N: asNumber(data.trait_N, 0.0),
    strategy: sanitizeText(data.strategy, ""),
    assignment_mode: sanitizeEnumText(data.assignment_mode, ASSIGNMENT_MODES, ""),
    assignment_source: sanitizeEnumText(
        data.assignment_source,
        ASSIGNMENT_SOURCES,
        "",
    ),
    assignment_buckets: sanitizeAssignmentBuckets(data.assignment_buckets),
    opener_template_id: sanitizeText(data.opener_template_id, ""),
    bridge_template_id: sanitizeText(data.bridge_template_id, ""),
    template_id: sanitizeText(data.template_id, ""),
    utterance: sanitizeText(data.utterance, ""),
    response: sanitizeText(data.response, ""),
    response_latency_ms: asNumber(data.response_latency_ms, -1),
    dialogue_duration_ms: asNumber(data.dialogue_duration_ms, -1),
    resolution_path: sanitizeText(data.resolution_path, ""),
    delivery_actor: sanitizeText(data.delivery_actor, ""),
    task_terminal_state: sanitizeEnumText(
        data.task_terminal_state,
        TASK_TERMINAL_STATES,
        "",
    ),
    task_failure_reason: sanitizeText(data.task_failure_reason, ""),
    task_terminal_at_ms: asNumber(data.task_terminal_at_ms, -1),
    score_delta: asNumber(data.score_delta, 0),
  };
  await requestRef.set(doc, {merge: true});
  return {request_id: requestId, help_request_key: helpRequestKey};
}

async function upsertDelegationTemplate(data) {
  const templateId = sanitizeText(data.template_id, "");
  if (templateId === "") {
    throw new Error("missing_template_id");
  }
  const templateRef = db.collection("delegation_templates").doc(templateId);
  const snapshot = await templateRef.get();
  const doc = {
    template_id: templateId,
    template_group: sanitizeText(data.template_group, ""),
    strategy: sanitizeText(data.strategy, ""),
    template_text: sanitizeText(data.template_text, ""),
  };
  if (!snapshot.exists) {
    doc.created_at = FieldValue.serverTimestamp();
  }
  await templateRef.set(doc, {merge: true});
  return {template_id: templateId};
}

async function upsertEpisodeLog(sessionId, participantId, data) {
  const episodeId = sanitizeText(data.episode_id, "");
  if (episodeId === "") {
    throw new Error("missing_episode_id");
  }
  const loggedSessionId = sanitizeText(data.session_id, sessionId);
  const episodeKey = `${encodeURIComponent(loggedSessionId)}__${encodeURIComponent(episodeId)}`;
  const episodeRef = db.collection("episodes").doc(episodeKey);
  const doc = {
    participant_id: sanitizeText(data.participant_id, participantId),
    session_id: loggedSessionId,
    session_source: sanitizeEnumText(
        data.session_source,
        SESSION_SOURCES,
        "standalone_test",
    ),
    experiment_version: sanitizeText(data.experiment_version, ""),
    episode_id: episodeId,
    episode_key: episodeKey,
    timestamp: sanitizeText(data.timestamp, ""),
    success: asBoolean(data.success, false),
    duration_ms: asNumber(data.duration_ms, 0),
    failure_reason: sanitizeText(data.failure_reason, ""),
  };
  await episodeRef.set(doc, {merge: true});
  return {episode_id: episodeId, episode_key: episodeKey};
}

async function upsertGameRunLog(sessionId, participantId, data) {
  const runId = sanitizeText(data.run_id, sessionId);
  if (runId === "") {
    throw new Error("missing_run_id");
  }
  const runRef = db.collection("game_runs").doc(runId);
  const doc = {
    run_id: runId,
    participant_id: sanitizeText(data.participant_id, participantId),
    session_id: sanitizeText(data.session_id, sessionId),
    session_source: sanitizeEnumText(
        data.session_source,
        SESSION_SOURCES,
        "standalone_test",
    ),
    experiment_version: sanitizeText(data.experiment_version, ""),
    run_outcome: sanitizeEnumText(data.run_outcome, new Set([
      "win",
      "end_of_day_loss",
      "score_threshold_loss",
    ]), ""),
    final_score: asNumber(data.final_score, 0),
    created_at: FieldValue.serverTimestamp(),
  };
  await runRef.set(doc, {merge: true});
  return {run_id: runId};
}

async function upsertApiFailureLog(sessionId, data) {
  const failureId = sanitizeText(data.failure_id, "");
  if (failureId === "") {
    throw new Error("missing_failure_id");
  }
  const failureRef = db.collection("api_failures").doc(failureId);
  const doc = {
    failure_id: failureId,
    session_id: sanitizeText(data.session_id, sessionId),
    session_source: sanitizeEnumText(
        data.session_source,
        SESSION_SOURCES,
        "standalone_test",
    ),
    episode_id: sanitizeText(data.episode_id, ""),
    request_id: sanitizeText(data.request_id, ""),
    api_name: sanitizeText(data.api_name, ""),
    event_type: sanitizeText(data.event_type, ""),
    http_status: asNumber(data.http_status, -1),
    error_code: sanitizeText(data.error_code, ""),
    error_message: sanitizeText(data.error_message, ""),
    client_timestamp_ms: asNumber(data.client_timestamp_ms, 0),
    created_at: FieldValue.serverTimestamp(),
  };
  await failureRef.set(doc, {merge: true});
  return {failure_id: failureId};
}

async function upsertRuntimeDebugEventLog(sessionId, data) {
  const debugEventId = sanitizeText(data.debug_event_id, "");
  if (debugEventId === "") {
    throw new Error("missing_debug_event_id");
  }
  const eventRef = db.collection("runtime_debug_events").doc(debugEventId);
  const doc = {
    debug_event_id: debugEventId,
    session_id: sanitizeText(data.session_id, sessionId),
    session_source: sanitizeEnumText(
        data.session_source,
        SESSION_SOURCES,
        "standalone_test",
    ),
    episode_id: sanitizeText(data.episode_id, ""),
    request_id: sanitizeText(data.request_id, ""),
    timestamp_ms: asNumber(data.timestamp_ms, 0),
    event_type: sanitizeEnumText(data.event_type, RUNTIME_DEBUG_EVENT_TYPES, ""),
    event_reason: sanitizeEnumText(data.event_reason, RUNTIME_DEBUG_EVENT_REASONS, ""),
    robot_task_id: sanitizeText(data.robot_task_id, ""),
    robot_step: sanitizeEnumText(data.robot_step, RUNTIME_DEBUG_ROBOT_STEPS, ""),
    delegation_scenario: sanitizeEnumText(data.delegation_scenario, RUNTIME_DEBUG_DELEGATION_SCENARIOS, ""),
    robot_x: sanitizeFiniteNumber(data.robot_x),
    robot_y: sanitizeFiniteNumber(data.robot_y),
    robot_target_x: sanitizeFiniteNumber(data.robot_target_x),
    robot_target_y: sanitizeFiniteNumber(data.robot_target_y),
    robot_battery_level: sanitizeFiniteNumber(data.robot_battery_level),
    robot_inventory_count: asNumber(data.robot_inventory_count, 0),
    player_active_tasks: asNumber(data.player_active_tasks, 0),
    has_navigation_path: asBoolean(data.has_navigation_path, false),
    path_length: asNumber(data.path_length, 0),
    moved_distance_px: sanitizeFiniteNumber(data.moved_distance_px),
    stuck_duration_ms: asNumber(data.stuck_duration_ms, 0),
    total_stuck_time_ms: asNumber(data.total_stuck_time_ms, 0),
    retry_count: asNumber(data.retry_count, 0),
    created_at: FieldValue.serverTimestamp(),
  };
  await eventRef.set(doc, {merge: true});
  return {debug_event_id: debugEventId};
}

function buildDialoguePrompts(body) {
  const fallback = sanitizeText(body.fallback, "Okay.");
  const model = sanitizeText(body.model, DEFAULT_MODEL) || DEFAULT_MODEL;
  const temperature = asNumber(body.temperature, DEFAULT_TEMPERATURE);

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

exports.apiAssignStrategy = onRequest(async (req, res) => {
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

  try {
    const result = await assignStrategyGlobally(body);
    res.status(200).json({
      ok: true,
      ...result,
    });
  } catch (err) {
    logger.error("apiAssignStrategy failed", err);
    res.status(500).json({error: "assignment_failed"});
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
  const participantId = sanitizeText(body.participant_id, sessionId);
  const eventType = sanitizeText(body.type, "");
  const data = asObject(body.data);
  const platform = sanitizeText(body.platform, "web");
  const buildVersion = sanitizeText(body.build_version, "");

  if (sessionId === "" || eventType === "") {
    res.status(400).json({error: "missing_session_or_type"});
    return;
  }

  try {
    let result = {};
    switch (eventType) {
      case "participant_upsert":
        result = await upsertParticipantLog(
            sessionId,
            platform,
            buildVersion,
            data,
        );
        break;
      case "help_request_upsert":
        result = await upsertHelpRequestLog(sessionId, participantId, data);
        break;
      case "episode_upsert":
        result = await upsertEpisodeLog(sessionId, participantId, data);
        break;
      case "game_run_upsert":
        result = await upsertGameRunLog(sessionId, participantId, data);
        break;
      case "template_upsert":
        result = await upsertDelegationTemplate(data);
        break;
      case "api_failure_upsert":
        result = await upsertApiFailureLog(sessionId, data);
        break;
      case "runtime_debug_event_upsert":
        result = await upsertRuntimeDebugEventLog(sessionId, data);
        break;
      default:
        res.status(400).json({error: "unsupported_log_type"});
        return;
    }

    res.status(200).json({
      ok: true,
      session_id: sessionId,
      type: eventType,
      ...result,
    });
  } catch (err) {
    logger.error("apiLog failed", err);
    res.status(500).json({error: "log_write_failed"});
  }
});
