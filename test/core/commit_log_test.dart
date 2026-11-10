import 'package:flutter_test/flutter_test.dart';

import 'package:eir/core/commit_log.dart';

RoomCommit makeCommit({
  required int seq,
  required String prevHash,
  String action = 'play',
  Map<String, Object?>? params,
  String? requestId,
  String signature = 'sig',
  int aclVersion = 1,
  int effectiveSharedMs = 1000,
}) {
  return RoomCommit(
    seq: seq,
    prevHash: prevHash,
    requestId: requestId,
    aclVersion: aclVersion,
    action: action,
    params: params ?? const {'positionMs': 0, 'rateMilli': 1000, 'itemId': 'i1'},
    effectiveSharedMs: effectiveSharedMs,
    roomId: 'room',
    sessionId: 'session',
    signature: signature,
  );
}

void main() {
  group('CommitChain', () {
    test('first commit links to genesis hash', () {
      final chain = CommitChain(genesisHash: 'a' * 64);
      final c1 = makeCommit(seq: 1, prevHash: 'a' * 64);
      expect(chain.classify(c1), CommitClass.ready);
      chain.markApplied(c1);
      expect(chain.lastSeq, 1);
      expect(chain.lastHash, c1.hash());
    });

    test('out-of-order commits are parked and drain in order', () {
      final chain = CommitChain(genesisHash: 'b' * 64);
      final c1 = makeCommit(seq: 1, prevHash: 'b' * 64, effectiveSharedMs: 1);
      final c2 = makeCommit(seq: 2, prevHash: c1.hash(), effectiveSharedMs: 2);
      final c3 = makeCommit(seq: 3, prevHash: c2.hash(), effectiveSharedMs: 3);
      // Receive 1, then 3 (gap), then 2.
      expect(chain.classify(c1), CommitClass.ready);
      chain.markApplied(c1);
      expect(chain.classify(c3), CommitClass.outOfOrder);
      chain.park(c3);
      expect(chain.pendingCount, 1);
      expect(chain.classify(c2), CommitClass.ready);
      chain.markApplied(c2);
      final drained = chain.drainReady();
      expect(drained, hasLength(1));
      expect(drained.single.seq, 3);
      expect(chain.lastSeq, 3);
    });

    test('duplicate commits are classified as duplicates', () {
      final chain = CommitChain(genesisHash: 'c' * 64);
      final c1 = makeCommit(seq: 1, prevHash: 'c' * 64);
      chain.markApplied(c1);
      expect(chain.classify(c1), CommitClass.duplicate);
    });

    test('prevHash mismatch on the next expected commit is chainRejected', () {
      final chain = CommitChain(genesisHash: 'd' * 64);
      final c1 = makeCommit(seq: 1, prevHash: 'd' * 64);
      chain.markApplied(c1);
      final c2 = makeCommit(seq: 2, prevHash: 'f' * 64);
      expect(chain.classify(c2), CommitClass.chainRejected);
    });

    test('pending buffer is bounded', () {
      final chain = CommitChain(genesisHash: 'e' * 64);
      for (var i = 5; i < 5 + kMaxPendingCommits + 10; i++) {
        chain.park(makeCommit(seq: i, prevHash: 'x' * 64));
      }
      expect(chain.pendingCount, kMaxPendingCommits);
    });

    test('request id tracking dedups retries', () {
      final chain = CommitChain(genesisHash: 'f' * 64);
      final c1 = makeCommit(seq: 1, prevHash: 'f' * 64, requestId: 'req-1');
      chain.markApplied(c1);
      expect(chain.hasAppliedRequest('req-1'), isTrue);
      expect(chain.seqForRequest('req-1'), 1);
      expect(chain.hasAppliedRequest('req-2'), isFalse);
    });

    test('resetTo snapshot position clears the pending buffer', () {
      final chain = CommitChain(genesisHash: '0' * 64);
      chain.park(makeCommit(seq: 9, prevHash: 'x' * 64));
      chain.resetTo(41, '1' * 64);
      expect(chain.lastSeq, 41);
      expect(chain.lastHash, '1' * 64);
      expect(chain.pendingCount, 0);
    });

    test('commit hash chains: each commit commits to the previous one', () {
      final c1 = makeCommit(seq: 1, prevHash: '9' * 64, effectiveSharedMs: 11);
      final c2a = makeCommit(seq: 2, prevHash: c1.hash(), effectiveSharedMs: 12);
      final c2b =
          makeCommit(seq: 2, prevHash: c1.hash(), effectiveSharedMs: 99);
      expect(c2a.hash(), isNot(c2b.hash()));
    });
  });

  group('RoomAcl', () {
    const ownerId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const alice = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const bob = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

    test('owner is always owner-role and can control', () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      expect(acl.canControl(ownerId), isTrue);
      expect(acl.canControl(alice), isFalse);
      expect(acl.roleOf(alice), 'none');
    });

    test('admit + grant + revoke lifecycle', () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      acl.applyCommit('member_admit', {'memberId': alice, 'role': 'member'});
      expect(acl.isAdmitted(alice), isTrue);
      expect(acl.canControl(alice), isFalse);
      final admitVersion = acl.version;

      acl.applyCommit('grant_admin', {'memberId': alice});
      expect(acl.roleOf(alice), 'admin');
      expect(acl.canControl(alice), isTrue);
      expect(acl.version, greaterThan(admitVersion));
      final grantVersion = acl.version;

      acl.applyCommit('revoke_admin', {'memberId': alice});
      expect(acl.roleOf(alice), 'member');
      expect(acl.canControl(alice), isFalse);
      expect(acl.version, greaterThan(grantVersion));
    });

    test('grant_admin to a non-admitted device fails', () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      final changed = acl.applyCommit('grant_admin', {'memberId': bob});
      expect(changed, isFalse);
      expect(acl.canControl(bob), isFalse);
    });

    test('revoke_admin on non-admin fails', () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      acl.applyCommit('member_admit', {'memberId': alice});
      expect(acl.applyCommit('revoke_admin', {'memberId': alice}), isFalse);
    });

    test('revoked admin immediately loses control rights (receiver-enforced)',
        () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      acl.applyCommit('member_admit', {'memberId': alice});
      acl.applyCommit('grant_admin', {'memberId': alice});
      expect(acl.canControl(alice), isTrue);
      // Owner revokes; the very next check fails.
      acl.applyCommit('revoke_admin', {'memberId': alice});
      expect(acl.canControl(alice), isFalse);
    });

    test('member_admit is idempotent and never demotes an admin', () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      acl.applyCommit('member_admit', {'memberId': alice});
      acl.applyCommit('grant_admin', {'memberId': alice});
      final v = acl.version;
      acl.applyCommit('member_admit', {'memberId': alice});
      expect(acl.roleOf(alice), 'admin');
      expect(acl.version, v); // no spurious version bump for a no-op admit
    });

    test('snapshot roundtrip preserves roles and version', () {
      final acl = RoomAcl(ownerDeviceId: ownerId);
      acl.applyCommit('member_admit', {'memberId': alice});
      acl.applyCommit('grant_admin', {'memberId': alice});
      final v = acl.version;
      final snap = acl.snapshot();

      final fresh = RoomAcl(ownerDeviceId: ownerId);
      fresh.loadSnapshot(snap, v);
      expect(fresh.roleOf(alice), 'admin');
      expect(fresh.version, v);
    });
  });
}
