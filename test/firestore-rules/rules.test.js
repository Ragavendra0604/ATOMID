import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, collection, getDocs } from 'firebase/firestore';

/**
 * The cloud half of Atomid's security model, which is one condition:
 * an account may touch `/users/{uid}/**` when `request.auth.uid == uid`, and
 * nothing else may be touched at all.
 *
 * The rule is short enough to read and believe, which is exactly why it was
 * never tested — and why a later edit widening it would have gone unnoticed.
 * These are the tests that make a regression visible.
 *
 * Requires the Firestore emulator (and therefore a JVM), so they run in CI
 * rather than as part of `flutter test`.
 */

const PROJECT_ID = 'atomid-rules-test';
const ALICE = 'alice-uid';
const BOB = 'bob-uid';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** Every collection the app actually writes to, so none is left unguarded. */
const COLLECTIONS = [
  'products',
  'customers',
  'sales',
  'suppliers',
  'purchases',
  'expenses',
  'expenseCategories',
  'inventoryMovements',
  'loyaltyTransactions',
  'customerLedgers',
  'supplierLedgers',
  'config',
];

describe('an account reaching its own subtree', () => {
  it('can read and write every collection it owns', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();

    for (const name of COLLECTIONS) {
      const ref = doc(db, `users/${ALICE}/${name}/record-1`);
      await assertSucceeds(setDoc(ref, { id: 'record-1', value: 1 }));
      await assertSucceeds(getDoc(ref));
      await assertSucceeds(deleteDoc(ref));
    }
  });

  it('can list a collection it owns', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(getDocs(collection(db, `users/${ALICE}/products`)));
  });

  it('can reach arbitrarily nested paths beneath itself', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    // The rule matches {document=**}, so depth must not matter.
    const deep = doc(db, `users/${ALICE}/products/p1/history/h1/detail/d1`);
    await assertSucceeds(setDoc(deep, { note: 'nested' }));
    await assertSucceeds(getDoc(deep));
  });

  it('can write its own top-level user document', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(setDoc(doc(db, `users/${ALICE}`), { name: 'Alice' }));
  });
});

describe('an account reaching someone else\'s subtree', () => {
  it('cannot read another account\'s records', async () => {
    // Seed as Bob with rules disabled, so the read is the only thing on trial.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${BOB}/sales/s1`), {
        grandTotal: 4200,
      });
    });

    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(getDoc(doc(db, `users/${BOB}/sales/s1`)));
  });

  it('cannot write into another account\'s records', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      setDoc(doc(db, `users/${BOB}/customers/c1`), { name: 'stolen' }),
    );
  });

  it('cannot delete another account\'s records', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${BOB}/products/p1`), { a: 1 });
    });

    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(deleteDoc(doc(db, `users/${BOB}/products/p1`)));
  });

  it('cannot list another account\'s collection', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(getDocs(collection(db, `users/${BOB}/products`)));
  });

  it('cannot reach a nested path under another account', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      getDoc(doc(db, `users/${BOB}/products/p1/history/h1`)),
    );
  });
});

describe('an unauthenticated caller', () => {
  it('cannot read any account\'s data', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${ALICE}/sales/s1`), { a: 1 });
    });

    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `users/${ALICE}/sales/s1`)));
  });

  it('cannot write anywhere', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, `users/${ALICE}/sales/s1`), { a: 1 }));
    await assertFails(setDoc(doc(db, 'anything/at/all/here'), { a: 1 }));
  });
});

describe('the catch-all deny', () => {
  it('refuses paths outside /users, even when signed in', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();

    // Includes the retired /stores tree from the removed multi-user model.
    for (const path of [
      'stores/store-1/products/p1',
      'stores/store-1',
      'products/p1',
      'admin/settings',
      'config/global',
    ]) {
      await assertFails(setDoc(doc(db, path), { a: 1 }));
      await assertFails(getDoc(doc(db, path)));
    }
  });

  it('refuses a top-level users listing', async () => {
    // Enumerating accounts must not be possible even for a valid account.
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(getDocs(collection(db, 'users')));
  });
});

describe('the rule depends on identity, not on document contents', () => {
  it('a forged uid field does not grant access', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      setDoc(doc(db, `users/${BOB}/sales/s1`), { uid: ALICE, ownerId: ALICE }),
    );
  });

  it('an account whose uid merely prefixes another gets nothing', async () => {
    // Guards against a future rule using startsWith or similar.
    const shortUid = 'alice';
    const db = testEnv.authenticatedContext(shortUid).firestore();
    await assertFails(getDoc(doc(db, `users/${ALICE}/sales/s1`)));
    await assertSucceeds(
      setDoc(doc(db, `users/${shortUid}/sales/s1`), { a: 1 }),
    );
  });
});

describe('sanity', () => {
  it('the rules file under test is the one the app deploys', () => {
    const rules = readFileSync('firestore.rules', 'utf8');
    assert.match(rules, /match \/users\/\{userId\}\/\{document=\*\*\}/);
    assert.match(rules, /request\.auth\.uid == userId/);
    assert.match(rules, /allow read, write: if false/);
  });
});
