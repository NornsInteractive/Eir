import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const workerSource = await readFile(
  path.join(here, '..', '..', 'cloudflare', '_worker.js'),
  'utf8',
);
const workerModule = await import(
  `data:text/javascript;base64,${Buffer.from(workerSource).toString('base64')}`
);
const { SignalingCoordinator } = workerModule;

const ROOM_ID = 'cccccccc-2222-3333-4444-555555555555';
const OTHER_ROOM_ID = 'abababab-2222-3333-4444-555555555555';
const TOKEN = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq';
const OTHER_TOKEN = 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ';
const SESSION_ID = '11111111-2222-3333-4444-555555555555';
const GENESIS_HASH = 'a'.repeat(64);

function identity(seed) {
  return {
    deviceId: seed.repeat(64).slice(0, 64),
    publicKey: `public-key-${seed}`,
  };
}

function fakeConn() {
  return {
    sent: [],
    roomId: null,
    deviceId: null,
    role: 'member',
    publicKey: null,
    displayName: '',
    avatar: '',
    joinedAt: Date.now(),
    iceCount: 0,
    send(message) {
      this.sent.push(message);
    },
    sendError(code) {
      this.sent.push({ type: 'error', code });
    },
    close() {},
  };
}

function last(conn) {
  return conn.sent[conn.sent.length - 1];
}

function createMessage(owner, overrides = {}) {
  return {
    type: 'create_room',
    protocolVersion: 1,
    roomId: ROOM_ID,
    token: TOKEN,
    deviceId: owner.deviceId,
    ownerPublicKey: owner.publicKey,
    sessionId: SESSION_ID,
    genesisHash: GENESIS_HASH,
    inviteEpoch: 1,
    ...overrides,
  };
}

function joinMessage(guest, overrides = {}) {
  return {
    type: 'join_room',
    protocolVersion: 1,
    deviceId: guest.deviceId,
    publicKey: guest.publicKey,
    ...overrides,
  };
}

async function createRoom(coordinator, owner, overrides = {}) {
  const conn = fakeConn();
  await coordinator.handleCreateRoom(conn, createMessage(owner, overrides));
  const reply = last(conn);
  assert.equal(reply.type, 'room_created');
  return { conn, reply };
}

test('room-code join without a token resolves the room credential', async () => {
  const coordinator = new SignalingCoordinator({}, {});
  const owner = identity('a');
  const guest = identity('b');
  const { reply } = await createRoom(coordinator, owner);

  const conn = fakeConn();
  await coordinator.handleJoinRoom(
    conn,
    joinMessage(guest, { roomCode: reply.roomCode }),
  );
  const accepted = last(conn);
  assert.equal(accepted.type, 'join_accepted');
  assert.equal(accepted.roomId, ROOM_ID);
  assert.equal(accepted.rejoined, false);
});

test('roomId-only join without a token is never authorized', async () => {
  const coordinator = new SignalingCoordinator({}, {});
  const owner = identity('a');
  const guest = identity('b');
  await createRoom(coordinator, owner);

  const denied = fakeConn();
  await coordinator.handleJoinRoom(
    denied,
    joinMessage(guest, { roomId: ROOM_ID }),
  );
  assert.deepEqual(last(denied), { type: 'error', code: 'invalid_invite' });

  const accepted = fakeConn();
  await coordinator.handleJoinRoom(
    accepted,
    joinMessage(guest, { roomId: ROOM_ID, token: TOKEN }),
  );
  assert.equal(last(accepted).type, 'join_accepted');
});

test('explicit token is validated even when a valid roomCode is supplied', async () => {
  const coordinator = new SignalingCoordinator({}, {});
  const owner = identity('a');
  const guest = identity('b');
  const { reply } = await createRoom(coordinator, owner);

  const conn = fakeConn();
  await coordinator.handleJoinRoom(
    conn,
    joinMessage(guest, { roomCode: reply.roomCode, token: OTHER_TOKEN }),
  );
  assert.deepEqual(last(conn), { type: 'error', code: 'invalid_invite' });
});

test('conflicting roomCode and roomId are rejected', async () => {
  const coordinator = new SignalingCoordinator({}, {});
  const owner = identity('a');
  const otherOwner = identity('c');
  const guest = identity('b');
  const created = await createRoom(coordinator, owner);
  await createRoom(coordinator, otherOwner, {
    roomId: OTHER_ROOM_ID,
    token: OTHER_TOKEN,
  });

  const conn = fakeConn();
  await coordinator.handleJoinRoom(
    conn,
    joinMessage(guest, {
      roomCode: created.reply.roomCode,
      roomId: OTHER_ROOM_ID,
      token: OTHER_TOKEN,
    }),
  );
  assert.deepEqual(last(conn), { type: 'error', code: 'invalid_message' });
});

test('room-code join keeps protocol and epoch validation', async () => {
  const coordinator = new SignalingCoordinator({}, {});
  const owner = identity('a');
  const guest = identity('b');
  const { reply } = await createRoom(coordinator, owner, { inviteEpoch: 2 });

  const wrongVersion = fakeConn();
  await coordinator.handleJoinRoom(
    wrongVersion,
    joinMessage(guest, { roomCode: reply.roomCode, protocolVersion: 2 }),
  );
  assert.deepEqual(last(wrongVersion), {
    type: 'error',
    code: 'protocol_version',
  });

  const staleEpoch = fakeConn();
  await coordinator.handleJoinRoom(
    staleEpoch,
    joinMessage(guest, { roomCode: reply.roomCode, inviteEpoch: 1 }),
  );
  assert.deepEqual(last(staleEpoch), { type: 'error', code: 'invite_stale' });
});

test('room-code join keeps the two-peer cap and idempotent rejoin', async () => {
  const coordinator = new SignalingCoordinator({}, {});
  const owner = identity('a');
  const guest = identity('b');
  const third = identity('c');
  const { reply } = await createRoom(coordinator, owner);

  const guestConn = fakeConn();
  await coordinator.handleJoinRoom(
    guestConn,
    joinMessage(guest, { roomCode: reply.roomCode }),
  );
  assert.equal(last(guestConn).type, 'join_accepted');

  const thirdConn = fakeConn();
  await coordinator.handleJoinRoom(
    thirdConn,
    joinMessage(third, { roomCode: reply.roomCode }),
  );
  assert.deepEqual(last(thirdConn), { type: 'error', code: 'invite_consumed' });

  coordinator.handleLeave(guestConn);
  const rejoin = fakeConn();
  await coordinator.handleJoinRoom(
    rejoin,
    joinMessage(guest, { roomCode: reply.roomCode }),
  );
  assert.equal(last(rejoin).type, 'join_accepted');
  assert.equal(last(rejoin).rejoined, true);
});
