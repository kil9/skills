// Roll20 게임 화면(app.roll20.net/editor/) 페이지 컨텍스트에서 실행하는 핸드아웃·캐릭터 헬퍼.
// 롤20 클라이언트의 비공식 객체(window.Campaign)를 쓴다 — 롤20 업데이트로 깨질 수 있다.
window.R20H = (() => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const readBlob = (m, field) => new Promise((resolve) => {
    let done = false;
    m._getLatestBlob(field, (v) => { done = true; resolve(v || ''); });
    setTimeout(() => { if (!done) resolve(null); }, 5000);
  });
  const decode = (v) => (v && /%u[0-9A-F]{4}|%3C/i.test(v) ? unescape(v) : v);
  const KINDS = {
    handout: { coll: () => Campaign.handouts, blobs: ['notes', 'gmnotes'] },
    character: { coll: () => Campaign.characters, blobs: ['bio', 'gmnotes'] },
  };

  async function ready() {
    for (let i = 0; i < 30; i++) {
      if (window.Campaign && Campaign.handouts && Campaign.characters && Campaign.players) return true;
      await sleep(1000);
    }
    throw new Error('Campaign 객체가 없다 — 게임 화면(/editor/)이 맞는지, 로딩이 끝났는지 확인');
  }

  function players() {
    return Campaign.players.models.map((p) => ({ id: p.id, name: p.get('displayname') }));
  }

  function list(kind = 'handout') {
    return KINDS[kind].coll().models.map((m) => ({
      id: m.id, name: m.get('name'), inplayerjournals: m.get('inplayerjournals'),
      controlledby: m.get('controlledby'), archived: m.get('archived'),
    }));
  }

  async function loadAttribs(c) {
    c.attribs.fetch(c.attribs);
    await sleep(1500);
    return c.attribs;
  }

  async function read(id, kind = 'handout') {
    const m = KINDS[kind].coll().get(id);
    if (!m) return null;
    const out = {
      id, name: m.get('name'), inplayerjournals: m.get('inplayerjournals'),
      controlledby: m.get('controlledby'), avatar: m.get('avatar'),
    };
    for (const b of KINDS[kind].blobs) out[b] = decode(await readBlob(m, b));
    if (kind === 'character') {
      out.attribs = Object.fromEntries((await loadAttribs(m)).map((a) => [a.get('name'), a.get('current')]));
    }
    return out;
  }

  // 'gm' | 'all' | [displayname, ...] → '' | 'all' | 'id,id'
  function resolvePlayers(spec) {
    if (!spec || spec === 'gm') return '';
    if (spec === 'all') return 'all';
    const ps = players();
    return spec.map((name) => {
      const p = ps.find((x) => x.name === name);
      if (!p) throw new Error(`플레이어 없음: ${name} (있는 이름: ${ps.map((x) => x.name).join(', ')})`);
      return p.id;
    }).join(',');
  }

  function rowId() {
    const C = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
    let t = Date.now(); let s = '';
    for (let i = 0; i < 8; i++) { s = C[t % 64] + s; t = Math.floor(t / 64); }
    for (let i = 0; i < 12; i++) s += C[Math.floor(Math.random() * 64)];
    return s;
  }

  function setAttr(c, name, value) {
    const v = String(value);
    const a = c.attribs.find((x) => x.get('name') === name);
    if (a) { if (a.get('current') !== v) a.save({ current: v }); } else c.attribs.create({ name, current: v });
  }

  // sheet: {attr: value, repeating_<section>: [{name, ...fields}]}
  // 반복 줄은 같은 섹션 안에서 name 필드가 같은 줄을 고치고, 없으면 새 줄을 만든다. 원본에 없는 줄은 건드리지 않는다.
  async function applySheet(c, sheet) {
    // 시트를 열어 둬야 시트 워커(파생값 계산)가 돈다.
    c.view.showDialog();
    for (let i = 0; i < 20 && (await loadAttribs(c)).length === 0; i++) await sleep(500);
    for (const [k, v] of Object.entries(sheet)) {
      if (!Array.isArray(v)) { setAttr(c, k, v); continue; }
      const prefix = `${k}_`;
      for (const row of v) {
        const nameAttr = c.attribs.find((a) => a.get('name').startsWith(prefix) && a.get('name').endsWith('_name') && a.get('current') === String(row.name));
        const id = nameAttr ? nameAttr.get('name').slice(prefix.length, -'_name'.length) : rowId();
        for (const [f, fv] of Object.entries(row)) setAttr(c, `${prefix}${id}_${f}`, fv);
      }
    }
    await sleep(2500);
    const bad = Object.entries(sheet).filter(([k, v]) => !Array.isArray(v))
      .filter(([k, v]) => { const a = c.attribs.find((x) => x.get('name') === k); return !a || a.get('current') !== String(v); })
      .map(([k]) => k);
    return bad;
  }

  // items: [{key, id?, name, visibleTo, controlledBy?, avatar?, archived?, <blob fields>, sheet?}]
  // 반환: [{key, id, action: created|updated|error, error?}]
  async function upsert(expectedCampaignId, kind, items) {
    await ready();
    if (String(window.campaign_id) !== String(expectedCampaignId)) {
      throw new Error(`열린 게임(${window.campaign_id})이 대상(${expectedCampaignId})과 다르다 — 아무것도 쓰지 않음`);
    }
    const { coll, blobs } = KINDS[kind];
    const results = [];
    for (const it of items) {
      try {
        const attrs = { name: it.name, inplayerjournals: resolvePlayers(it.visibleTo) };
        if (it.controlledBy !== undefined) attrs.controlledby = resolvePlayers(it.controlledBy);
        if (it.avatar !== undefined) attrs.avatar = it.avatar;
        if (it.archived !== undefined) attrs.archived = it.archived;
        let m = it.id && coll().get(it.id);
        let action = 'updated';
        if (it.id && !m) {
          results.push({ key: it.key, id: it.id, action: 'error', error: 'roll20.json 의 id 가 게임에 없다(롤20에서 지워졌나?)' });
          continue;
        }
        if (!m) {
          const dup = coll().models.filter((x) => x.get('name') === it.name);
          if (dup.length) {
            results.push({ key: it.key, action: 'error', error: `같은 이름이 이미 있다: ${dup.map((x) => x.id).join(', ')}` });
            continue;
          }
          m = coll().create({ controlledby: '', archived: false, ...attrs });
          action = 'created';
          await sleep(1000);
        } else {
          m.save(attrs);
        }
        const blobVals = Object.fromEntries(blobs.map((b) => [b, it[b] || '']));
        m.updateBlobs(blobVals);
        await sleep(800);
        const errs = [];
        for (const b of blobs) if ((await readBlob(m, b)) !== blobVals[b]) errs.push(`${b} 되읽기 불일치`);
        if (kind === 'character' && it.sheet) {
          const bad = await applySheet(m, it.sheet);
          if (bad.length) errs.push(`시트 값이 안 맞음: ${bad.join(', ')}(시트 워커가 바꿨을 수 있다)`);
        }
        results.push({ key: it.key, id: m.id, action: errs.length ? 'error' : action, error: errs.join('; ') || undefined });
      } catch (e) {
        results.push({ key: it.key, id: it.id, action: 'error', error: e.message });
      }
    }
    return results;
  }

  function remove(id, kind = 'handout') {
    const m = KINDS[kind].coll().get(id);
    if (!m) return false;
    m.destroy();
    return true;
  }

  return { ready, players, list, read, upsert, remove };
})();
