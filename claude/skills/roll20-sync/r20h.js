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
    // 시트를 열어 둬야 시트 워커(파생값 계산)가 돈다. 단 속성을 다 불러오기 전에 열면 시트가 빈 캐릭터로
    // 여기고 초기화(기본 물품 중복 생성, 행동 점수를 플레이북 초기값으로 되돌림)를 다시 돌린다. 반드시 먼저 불러온다.
    for (let i = 0; i < 6 && (await loadAttribs(c)).length === 0; i++) await sleep(500);
    c.view.showDialog();
    await sleep(3000);
    await loadAttribs(c);
    // 플레이북 이름을 바꾸면 시트 워커가 기본 능력·물품·지인을 채우고 행동 점수·설명을 초기값으로 덮는다.
    // 그래서 플레이북을 먼저 쓰고 자동 채움이 끝난 뒤 나머지를 쓴다.
    if ('playbook' in sheet) {
      const a = c.attribs.find((x) => x.get('name') === 'playbook');
      if (!a || a.get('current') !== String(sheet.playbook)) {
        setAttr(c, 'playbook', sheet.playbook);
        await sleep(5000);
        await loadAttribs(c);
      }
    }
    for (const [k, v] of Object.entries(sheet)) {
      if (k === 'playbook') continue;
      if (!Array.isArray(v)) { setAttr(c, k, v); continue; }
      const prefix = `${k}_`;
      for (const row of v) {
        const nameAttr = c.attribs.find((a) => a.get('name').startsWith(prefix) && a.get('name').endsWith('_name') && a.get('current') === String(row.name));
        const id = nameAttr ? nameAttr.get('name').slice(prefix.length, -'_name'.length) : rowId();
        for (const [f, fv] of Object.entries(row)) setAttr(c, `${prefix}${id}_${f}`, fv);
        // 자동 채움이 다시 돌면 autogen 표시가 붙은 줄을 지우고 새로 만든다. 손댄 줄은 표시를 떼어 지킨다.
        const auto = c.attribs.find((a) => a.get('name') === `${prefix}${id}_autogen`);
        if (auto && auto.get('current')) auto.save({ current: '' });
      }
    }
    // 자동 채움은 changed_attributes(시트 화면에서 사람이 바꾼 속성 목록)에 없는 값을 초기값으로 덮는다.
    // 스크립트로 쓴 값은 이 목록에 안 올라가므로 직접 올린다.
    const scalars = Object.keys(sheet).filter((k) => k !== 'playbook' && !Array.isArray(sheet[k]));
    const ca = c.attribs.find((a) => a.get('name') === 'changed_attributes');
    const merged = [...new Set([...((ca && ca.get('current')) || '').split(','), ...scalars])].filter(Boolean).join(',');
    setAttr(c, 'changed_attributes', merged);
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

  // 페이지(맵)와 그 위의 그래픽(맵 그림·토큰).
  // items: [{key, id?, name, width, height, showgrid?, graphics: [{gkey, id?, layer, imgsrc, left, top, width, height,
  //          name?, character?(캐릭터 id), bar1?(연결할 시트 속성 이름), bar1_max?}]}]
  // 반환: [{key, id, action, graphics: {gkey: id}, error?}]
  // 그래픽 위치(left/top)는 처음 놓을 때만 쓴다 — 플레이 중에 옮긴 토큰을 되돌리지 않는다.
  // page.thegraphics 는 그 페이지를 GM 화면에 띄워야 생긴다. switchPageById 는 GM 자신의 화면만 바꾸고
  // 플레이어 리본(playerpageid)은 건드리지 않는다. 끝나면 원래 보던 페이지로 돌아간다.
  async function upsertPages(expectedCampaignId, items) {
    await ready();
    if (String(window.campaign_id) !== String(expectedCampaignId)) {
      throw new Error(`열린 게임(${window.campaign_id})이 대상(${expectedCampaignId})과 다르다 — 아무것도 쓰지 않음`);
    }
    const back = Campaign.activePage() && Campaign.activePage().id;
    const results = [];
    for (const it of items) {
      const out = { key: it.key, graphics: {} };
      try {
        const attrs = { name: it.name, width: it.width, height: it.height };
        if (it.showgrid !== undefined) attrs.showgrid = it.showgrid;
        let p = it.id && Campaign.pages.get(it.id);
        if (it.id && !p) throw new Error('roll20.json 의 페이지 id 가 게임에 없다(롤20에서 지워졌나?)');
        out.action = p ? 'updated' : 'created';
        if (p) p.save(attrs); else { p = Campaign.pages.create(attrs); await sleep(1500); }
        out.id = p.id;
        await Campaign.switchPageById(p.id);
        for (let i = 0; i < 20 && !p.thegraphics; i++) await sleep(500);
        if (!p.thegraphics) throw new Error('페이지 그래픽을 불러오지 못했다');
        for (const g of it.graphics) {
          const ga = { layer: g.layer, imgsrc: g.imgsrc, width: g.width, height: g.height, name: g.name || '' };
          let c = null;
          if (g.character) {
            c = Campaign.characters.get(g.character);
            if (!c) throw new Error(`${g.gkey}: 캐릭터 id 가 게임에 없다`);
            ga.represents = c.id;
            ga.showname = true;
            if (g.bar1) {
              await loadAttribs(c);
              const a = c.attribs.find((x) => x.get('name') === g.bar1);
              if (!a) throw new Error(`${g.gkey}: 시트 속성 ${g.bar1} 이 없다`);
              Object.assign(ga, { bar1_link: a.id, bar1_value: a.get('current'), bar1_max: g.bar1_max ?? a.get('max') ?? '' });
            }
          }
          let gr = g.id && p.thegraphics.get(g.id);
          if (gr) gr.save(ga);
          else {
            gr = p.thegraphics.create({ ...ga, left: g.left, top: g.top });
            await sleep(800);
            // 캐릭터 토큰을 처음 놓을 때 그 토큰을 캐릭터의 기본 토큰(저널에서 끌어다 놓을 때 쓰이는 것)으로도 저장한다.
            if (c) await c.saveDefaultToken(gr.toJSON());
          }
          out.graphics[g.gkey] = gr.id;
        }
      } catch (e) {
        out.action = 'error';
        out.error = e.message;
      }
      results.push(out);
    }
    if (back) await Campaign.switchPageById(back);
    return results;
  }

  function remove(id, kind = 'handout') {
    const m = KINDS[kind].coll().get(id);
    if (!m) return false;
    m.destroy();
    return true;
  }

  return { ready, players, list, read, upsert, upsertPages, remove };
})();
