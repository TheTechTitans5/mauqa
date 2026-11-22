import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isoToPktLocal, pktLocalToIso, rowsToTree, slugify, toCsv, treeToRows, validateTree, type RuleNode } from '../src/lib.ts';

test('CSV export escapes and neutralises formula injection', () => {
  const csv = toCsv([{ title: 'A, "quoted"', n: 1 }, { title: '=HYPERLINK("x")', extra: { a: 1 } }]);
  assert.equal(csv.split('\n')[0], 'title,n,extra');
  assert.ok(csv.includes('"A, ""quoted"""'));
  assert.ok(csv.includes(`"'=HYPERLINK(""x"")"`), csv);
  assert.equal(toCsv([]), '');
});

test('rule tree round-trips through rows', () => {
  const tree: RuleNode = { kind: 'group', op: 'and', mandatory: true, children: [
    { kind: 'criterion', type: 'cgpa_min', params: { min: 3 }, label: 'CGPA', mandatory: true },
    { kind: 'group', op: 'or', mandatory: true, children: [
      { kind: 'criterion', type: 'gender_in', params: { genders: ['female'] }, mandatory: true },
      { kind: 'criterion', type: 'disability_required', params: {}, mandatory: true },
    ] },
  ] };
  let i = 0;
  const rows = treeToRows(tree, 'opp', () => `id${++i}`);
  assert.equal(rows.length, 5);
  assert.equal(rows[0].parent_id, null);
  assert.equal(rows.filter((r) => r.parent_id === rows[0].id).length, 2);
  assert.deepEqual(JSON.parse(JSON.stringify(rowsToTree(rows))), JSON.parse(JSON.stringify(tree)));
});

test('legacy flat rules (several roots) become an implicit AND', () => {
  const t = rowsToTree([
    { id: 'a', opportunity_id: 'o', parent_id: null, node_type: 'criterion', criterion_type: 'age_range', params: { max: 25 }, is_mandatory: true, sort_order: 1 },
    { id: 'b', opportunity_id: 'o', parent_id: null, node_type: 'criterion', criterion_type: 'province_in', params: { provinces: ['Sindh'] }, is_mandatory: true, sort_order: 0 },
  ]);
  assert.equal(t.op, 'and');
  assert.equal(t.children?.[0].type, 'province_in');
});

test('rule validation catches empty groups and incomplete criteria', () => {
  const errs = validateTree({ kind: 'group', op: 'and', mandatory: true, children: [
    { kind: 'group', op: 'or', mandatory: true, children: [] },
    { kind: 'criterion', type: 'cgpa_min', params: {}, mandatory: true },
    { kind: 'criterion', type: 'institution_whitelist', params: { names: [] }, mandatory: true },
    { kind: 'criterion', type: 'nope', params: {}, mandatory: true },
  ] });
  assert.equal(errs.length, 4);
  assert.deepEqual(validateTree({ kind: 'group', op: 'and', mandatory: true, children: [
    { kind: 'criterion', type: 'institution_whitelist', params: { list_available: false }, mandatory: true }] }), []);
});

test('PKT datetime conversion', () => {
  assert.equal(pktLocalToIso('2026-12-15T23:59'), '2026-12-15T18:59:00.000Z');
  assert.equal(isoToPktLocal('2026-12-15T18:59:00Z'), '2026-12-15T23:59');
  assert.equal(pktLocalToIso('garbage'), null);
  assert.equal(slugify('  Higher Education Commission (HEC)  '), 'higher-education-commission-hec');
});
