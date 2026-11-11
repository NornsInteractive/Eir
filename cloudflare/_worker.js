/**
 * Eir - Cloudflare Pages / Workers Single-Port Unified Web & Signaling Server
 * 
 * Provides:
 * 1. Static asset serving for Flutter Web with mandatory COOP & COEP headers.
 * 2. Full-featured WebSocket Signaling Server on `/ws` (and root `/`).
 * 3. Durable Object `SignalingCoordinator` for global edge consistency.
 */

const kProtocolVersion = 1;
const kMaxMessageBytes = 32 * 1024;
const kMaxSdpBytes = 16 * 1024;
const kMaxCandidateBytes = 2 * 1024;
const kMaxIceCandidatesPerPeer = 96;
const kMaxRooms = 256;
const kMaxPeersPerRoom = 2;
const kRateBurst = 60;
const kRateRefillPerSecond = 20;

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX_64 = /^[0-9a-f]{64}$/i;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const DEVICE_ID_PATTERN = /^[0-9a-f]{64}$/i;

async function sha256Hex(text) {
  const enc = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', enc);
  return Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

function ctEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

class PeerConn {
  constructor(ws, coordinator) {
    this.ws = ws;
    this.coordinator = coordinator;
    this.roomId = null;
    this.deviceId = null;
    this.role = 'member';
    this.publicKey = null;
    this.joinedAt = Date.now();
    this.tokens = kRateBurst;
    this.lastRefill = Date.now();
    this.iceCount = 0;
  }

  takeRateToken() {
    const now = Date.now();
    const elapsedSec = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(kRateBurst, this.tokens + elapsedSec * kRateRefillPerSecond);
    this.lastRefill = now;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }

  send(msg) {
    try {
      this.ws.send(JSON.stringify(msg));
    } catch (_) {}
  }

  sendError(code) {
    this.send({ type: 'error', code });
  }

  close(code, reason) {
    try {
      this.ws.close(code, reason);
    } catch (_) {}
  }
}

class Room {
  constructor({ roomId, tokenDigest, ownerDeviceId, ownerPublicKey, sessionId, genesisHash, inviteEpoch, roomCode, rawToken }) {
    this.roomId = roomId;
    this.tokenDigest = tokenDigest;
    this.ownerDeviceId = ownerDeviceId;
    this.ownerPublicKey = ownerPublicKey;
    this.sessionId = sessionId;
    this.genesisHash = genesisHash;
    this.inviteEpoch = inviteEpoch;
    this.roomCode = roomCode;
    this.rawToken = rawToken;
    this.inviteConsumedBy = null;
    this.peers = new Map(); // deviceId -> PeerConn
  }

  attach(conn, deviceId) {
    const existing = this.peers.get(deviceId);
    if (existing && existing !== conn) {
      existing.close(1008, 'superseded');
    }
    this.peers.set(deviceId, conn);
  }

  remove(deviceId, conn) {
    if (this.peers.get(deviceId) === conn) {
      this.peers.delete(deviceId);
    }
  }

  broadcast(msg, exceptDeviceId = null) {
    for (const [id, peer] of this.peers.entries()) {
      if (id !== exceptDeviceId) {
        peer.send(msg);
      }
    }
  }
}

export class SignalingCoordinator {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.rooms = new Map(); // roomId -> Room
    this.codeToRoomId = new Map(); // roomCode -> roomId
    this.roomIdToCode = new Map(); // roomId -> roomCode
    this.reapTimers = new Map(); // roomId -> timer
    this.kReapGraceMs = 5 * 60 * 1000; // 5 minutes grace period for empty rooms
  }

  scheduleRoomReap(roomId) {
    this.cancelRoomReap(roomId);
    const timer = setTimeout(() => {
      this.reapTimers.delete(roomId);
      const room = this.rooms.get(roomId);
      if (room && room.peers.size === 0) {
        this.removeRoom(roomId);
      }
    }, this.kReapGraceMs);
    this.reapTimers.set(roomId, timer);
  }

  cancelRoomReap(roomId) {
    const timer = this.reapTimers.get(roomId);
    if (timer) {
      clearTimeout(timer);
      this.reapTimers.delete(roomId);
    }
  }

  generateRoomCode() {
    for (let i = 0; i < 10000; i++) {
      const code = String(Math.floor(100000 + Math.random() * 900000));
      if (!this.codeToRoomId.has(code)) return code;
    }
    return String(Math.floor(100000 + Math.random() * 900000));
  }

  removeRoom(roomId) {
    this.cancelRoomReap(roomId);
    this.rooms.delete(roomId);
    const code = this.roomIdToCode.get(roomId);
    if (code) {
      this.codeToRoomId.delete(code);
      this.roomIdToCode.delete(roomId);
    }
  }

  async fetch(request) {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected WebSocket', { status: 426 });
    }
    if (this.rooms.size >= kMaxRooms) {
      return new Response(JSON.stringify({ error: 'server_full' }), {
        status: 429,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();

    const conn = new PeerConn(server, this);

    server.addEventListener('message', async (event) => {
      if (!conn.takeRateToken()) {
        conn.sendError('rate_limited');
        return;
      }
      const raw = event.data;
      if (typeof raw !== 'string' || raw.length > kMaxMessageBytes) {
        conn.sendError('oversized_message');
        return;
      }
      let msg;
      try {
        msg = JSON.parse(raw);
      } catch (_) {
        conn.sendError('invalid_message');
        return;
      }
      if (!msg || typeof msg !== 'object') return;
      await this.handleMessage(conn, msg);
    });

    server.addEventListener('close', () => {
      this.handleClose(conn);
    });

    server.addEventListener('error', () => {
      this.handleClose(conn);
    });

    return new Response(null, { status: 101, webSocket: client });
  }

  handleClose(conn) {
    this.handlePeerDepart(conn);
  }

  handlePeerDepart(conn) {
    if (!conn.roomId || !conn.deviceId) return;
    const room = this.rooms.get(conn.roomId);
    const deviceId = conn.deviceId;
    conn.roomId = null;
    conn.deviceId = null;
    if (!room) return;
    const wasOwner = room.ownerDeviceId === deviceId;
    room.remove(deviceId, conn);
    room.broadcast({
      type: 'member_left',
      roomId: room.roomId,
      deviceId,
    });
    if (wasOwner && room.peers.size > 0) {
      const candidates = Array.from(room.peers.values());
      candidates.sort((a, b) => {
        const aAdmin = a.role === 'admin' ? 1 : 0;
        const bAdmin = b.role === 'admin' ? 1 : 0;
        if (aAdmin !== bAdmin) return bAdmin - aAdmin;
        return a.joinedAt - b.joinedAt;
      });
      const successor = candidates[0];
      successor.role = 'owner';
      room.ownerDeviceId = successor.deviceId;
      if (successor.publicKey) {
        room.ownerPublicKey = successor.publicKey;
      }
      room.broadcast({
        type: 'owner_changed',
        roomId: room.roomId,
        newOwnerDeviceId: successor.deviceId,
        previousOwnerDeviceId: deviceId,
      });
    }
    if (room.peers.size === 0) {
      this.scheduleRoomReap(room.roomId);
    }
  }

  async handleMessage(conn, msg) {
    const type = msg.type;
    switch (type) {
      case 'ping':
        conn.send({ type: 'pong' });
        break;
      case 'create_room':
        await this.handleCreateRoom(conn, msg);
        break;
      case 'query_room_code':
        this.handleQueryRoomCode(conn, msg);
        break;
      case 'join_room':
        await this.handleJoinRoom(conn, msg);
        break;
      case 'signal':
        this.handleSignal(conn, msg);
        break;
      case 'leave':
        this.handleLeave(conn);
        break;
      case 'disband':
        this.handleDisband(conn);
        break;
      default:
        conn.sendError('unknown_message');
    }
  }

  async handleCreateRoom(conn, msg) {
    const { roomId, token, deviceId, ownerPublicKey, sessionId, genesisHash, inviteEpoch, protocolVersion, roomCode: requestedCode } = msg;
    if (protocolVersion !== kProtocolVersion) return conn.sendError('protocol_version');
    if (!roomId || !UUID_V4.test(roomId)) return conn.sendError('invalid_message');
    if (!token || !TOKEN_PATTERN.test(token)) return conn.sendError('invalid_message');
    if (!deviceId || !DEVICE_ID_PATTERN.test(deviceId)) return conn.sendError('invalid_message');
    if (!ownerPublicKey || typeof ownerPublicKey !== 'string') return conn.sendError('invalid_message');
    if (!sessionId || !UUID_V4.test(sessionId)) return conn.sendError('invalid_message');
    if (!genesisHash || !HEX_64.test(genesisHash)) return conn.sendError('invalid_message');

    const existing = this.rooms.get(roomId);
    if (existing) {
      if (existing.ownerDeviceId === deviceId &&
          existing.genesisHash === genesisHash &&
          existing.sessionId === sessionId) {
        this.cancelRoomReap(roomId);
        existing.attach(conn, deviceId);
        conn.roomId = roomId;
        conn.deviceId = deviceId;
        const currentCode = existing.roomCode || this.roomIdToCode.get(roomId);
        conn.send({
          type: 'room_created',
          roomId,
          roomCode: currentCode,
          sessionId: existing.sessionId,
          inviteEpoch: existing.inviteEpoch,
          rejoined: true,
        });
        return;
      }
      return conn.sendError('room_exists');
    }

    if (this.rooms.size >= kMaxRooms) return conn.sendError('server_full');

    const digest = await sha256Hex(token);
    let roomCode = (typeof requestedCode === 'string' && /^\d{6}$/.test(requestedCode) && !this.codeToRoomId.has(requestedCode))
      ? requestedCode
      : this.generateRoomCode();
    this.codeToRoomId.set(roomCode, roomId);
    this.roomIdToCode.set(roomId, roomCode);

    const room = new Room({
      roomId,
      tokenDigest: digest,
      ownerDeviceId: deviceId,
      ownerPublicKey,
      sessionId,
      genesisHash,
      inviteEpoch: typeof inviteEpoch === 'number' ? inviteEpoch : 1,
      roomCode,
      rawToken: token,
    });

    this.rooms.set(roomId, room);
    room.attach(conn, deviceId);
    conn.roomId = roomId;
    conn.deviceId = deviceId;
    conn.role = 'owner';
    conn.publicKey = ownerPublicKey;
    conn.displayName = typeof msg.displayName === 'string' ? msg.displayName.trim() : '';
    conn.avatar = typeof msg.avatar === 'string' ? msg.avatar.trim() : '';
    conn.joinedAt = Date.now();

    conn.send({
      type: 'room_created',
      roomId,
      roomCode,
      sessionId: room.sessionId,
      inviteEpoch: room.inviteEpoch,
    });
  }

  handleQueryRoomCode(conn, msg) {
    const code = typeof msg.roomCode === 'string' ? msg.roomCode.trim() : null;
    if (!code) return conn.sendError('invalid_message');
    const roomId = this.codeToRoomId.get(code);
    if (!roomId) return conn.sendError('room_not_found');
    const room = this.rooms.get(roomId);
    if (!room) return conn.sendError('room_not_found');
    conn.send({
      type: 'room_code_info',
      roomCode: code,
      roomId,
      sessionId: room.sessionId,
      ownerPublicKey: room.ownerPublicKey,
      genesisHash: room.genesisHash,
      inviteEpoch: room.inviteEpoch,
      token: room.rawToken,
    });
  }

  async handleJoinRoom(conn, msg) {
    let roomId = msg.roomId;
    if ((!roomId || !UUID_V4.test(roomId)) && typeof msg.roomCode === 'string') {
      const code = msg.roomCode.trim();
      roomId = this.codeToRoomId.get(code);
    }
    let token = msg.token;
    if (!token && roomId && this.rooms.has(roomId)) {
      token = this.rooms.get(roomId).rawToken;
    }
    const { deviceId, publicKey, protocolVersion } = msg;
    const inviteEpoch = typeof msg.inviteEpoch === 'number' ? msg.inviteEpoch : (roomId && this.rooms.has(roomId) ? this.rooms.get(roomId).inviteEpoch : 1);
    if (protocolVersion !== kProtocolVersion) return conn.sendError('protocol_version');
    if (!roomId || !UUID_V4.test(roomId)) return conn.sendError('invalid_message');
    if (!token || !TOKEN_PATTERN.test(token)) return conn.sendError('invalid_invite');
    if (!deviceId || !DEVICE_ID_PATTERN.test(deviceId)) return conn.sendError('invalid_message');
    if (!publicKey || typeof publicKey !== 'string') return conn.sendError('invalid_message');

    const room = this.rooms.get(roomId);
    if (!room) return conn.sendError('room_not_found');
    this.cancelRoomReap(roomId);
    if (inviteEpoch !== room.inviteEpoch) return conn.sendError('invite_stale');

    const digest = await sha256Hex(token);
    if (!ctEqualHex(room.tokenDigest, digest)) return conn.sendError('invalid_invite');

    const getMembers = () => Array.from(room.peers.values()).map(p => ({
      deviceId: p.deviceId,
      role: p.role || 'member',
      displayName: p.displayName || '',
      avatar: p.avatar || '',
      joinedAt: p.joinedAt || Date.now(),
    }));

    if (room.peers.has(deviceId)) {
      room.attach(conn, deviceId);
      conn.roomId = roomId;
      conn.deviceId = deviceId;
      if (typeof msg.displayName === 'string') conn.displayName = msg.displayName.trim();
      if (typeof msg.avatar === 'string') conn.avatar = msg.avatar.trim();
      conn.send({
        type: 'join_accepted',
        roomId,
        sessionId: room.sessionId,
        genesisHash: room.genesisHash,
        ownerPublicKey: room.ownerPublicKey,
        inviteEpoch: room.inviteEpoch,
        rejoined: true,
        members: getMembers(),
      });
      room.broadcast({
        type: 'member_joined',
        roomId,
        deviceId,
        publicKey: conn.publicKey,
        displayName: conn.displayName || '',
        avatar: conn.avatar || '',
        joinedAt: conn.joinedAt || Date.now(),
        rejoined: true,
      }, deviceId);
      return;
    }

    if (room.inviteConsumedBy !== null && room.inviteConsumedBy !== deviceId) {
      return conn.sendError('invite_consumed');
    }
    if (room.peers.size >= kMaxPeersPerRoom) {
      return conn.sendError('room_full');
    }

    room.inviteConsumedBy = deviceId;
    room.attach(conn, deviceId);
    conn.roomId = roomId;
    conn.deviceId = deviceId;
    conn.role = (deviceId === room.ownerDeviceId) ? 'owner' : 'member';
    conn.publicKey = msg.publicKey || null;
    conn.displayName = typeof msg.displayName === 'string' ? msg.displayName.trim() : '';
    conn.avatar = typeof msg.avatar === 'string' ? msg.avatar.trim() : '';
    conn.joinedAt = Date.now();

    conn.send({
      type: 'join_accepted',
      roomId,
      sessionId: room.sessionId,
      genesisHash: room.genesisHash,
      ownerPublicKey: room.ownerPublicKey,
      inviteEpoch: room.inviteEpoch,
      rejoined: false,
      members: getMembers(),
    });
    room.broadcast({
      type: 'member_joined',
      roomId,
      deviceId,
      publicKey: conn.publicKey,
      displayName: conn.displayName || '',
      avatar: conn.avatar || '',
      joinedAt: conn.joinedAt || Date.now(),
      rejoined: false,
    }, deviceId);
  }

  handleSignal(conn, msg) {
    if (!conn.roomId || !conn.deviceId) return conn.sendError('not_in_room');
    const room = this.rooms.get(conn.roomId);
    if (!room) return conn.sendError('not_in_room');

    const kind = msg.kind;
    if (kind !== 'offer' && kind !== 'answer' && kind !== 'ice' && kind !== 'room_msg' && kind !== 'tailcat_addr') {
      return conn.sendError('invalid_message');
    }

    let outbound;
    if (kind === 'offer' || kind === 'answer') {
      const sdp = msg.sdp;
      if (!sdp || typeof sdp !== 'object') return conn.sendError('invalid_message');
      const { type, sdp: body } = sdp;
      if (type !== kind || typeof body !== 'string' || body.length > kMaxSdpBytes) {
        return conn.sendError('invalid_message');
      }
      outbound = {
        type: 'signal',
        roomId: room.roomId,
        from: conn.deviceId,
        kind,
        sdp: { type, sdp: body },
      };
    } else if (kind === 'tailcat_addr') {
      const addr = msg.addr;
      if (!addr || typeof addr !== 'string' || addr.length > 2048) return conn.sendError('invalid_message');
      outbound = {
        type: 'signal',
        roomId: room.roomId,
        from: conn.deviceId,
        kind: 'tailcat_addr',
        addr,
      };
    } else if (kind === 'room_msg') {
      const payload = msg.payload;
      if (!payload || typeof payload !== 'object') return conn.sendError('invalid_message');
      outbound = {
        type: 'signal',
        roomId: room.roomId,
        from: conn.deviceId,
        kind: 'room_msg',
        payload,
      };
    } else {
      const cand = msg.candidate;
      if (!cand || typeof cand !== 'object') return conn.sendError('invalid_message');
      conn.iceCount += 1;
      if (conn.iceCount > kMaxIceCandidatesPerPeer) return conn.sendError('rate_limited');
      const { candidate, sdpMid, sdpMLineIndex } = cand;
      if (typeof candidate !== 'string' || candidate.length > kMaxCandidateBytes) {
        return conn.sendError('invalid_message');
      }
      outbound = {
        type: 'signal',
        roomId: room.roomId,
        from: conn.deviceId,
        kind: 'ice',
        candidate: { candidate, sdpMid, sdpMLineIndex },
      };
    }

    room.broadcast(outbound, conn.deviceId);
  }

  handleLeave(conn) {
    this.handlePeerDepart(conn);
  }

  handleDisband(conn) {
    if (!conn.roomId || !conn.deviceId) return conn.sendError('not_in_room');
    const room = this.rooms.get(conn.roomId);
    if (!room) return conn.sendError('not_in_room');
    if (room.ownerDeviceId !== conn.deviceId) return conn.sendError('permission_denied');

    this.cancelRoomReap(room.roomId);
    this.removeRoom(room.roomId);
    for (const peer of room.peers.values()) {
      peer.send({
        type: 'disbanded',
        roomId: room.roomId,
        reason: 'disbanded',
      });
      peer.close(1000, 'disbanded');
    }
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. WebSocket Upgrade handling (/ws or root with Upgrade header)
    const isWs = request.headers.get('Upgrade') === 'websocket' || url.pathname === '/ws';
    if (isWs) {
      if (env && env.ROOMS) {
        const id = env.ROOMS.idFromName('global_signaling');
        const stub = env.ROOMS.get(id);
        return stub.fetch(request);
      }
      return new Response('WebSocket signaling requires Durable Objects binding (ROOMS).', { status: 501 });
    }

    // 2. Static Asset delivery with COOP and COEP
    if (env && env.ASSETS) {
      const response = await env.ASSETS.fetch(request);
      const headers = new Headers(response.headers);
      headers.set('Cross-Origin-Opener-Policy', 'same-origin');
      headers.set('Cross-Origin-Embedder-Policy', 'credentialless');
      headers.set('Access-Control-Allow-Origin', '*');
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    }

    return new Response('Eir Unified Web & Signaling Server (Cloudflare)', { status: 200 });
  },
};
