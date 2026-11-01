// Roll20 게임 화면(app.roll20.net/editor/) 페이지 컨텍스트에서 실행하는 핸드아웃 헬퍼.
// 롤20 클라이언트의 비공식 객체(window.Campaign)를 쓴다 — 롤20 업데이트로 깨질 수 있다.
window.R20H = (() => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const readBlob = (h, field) => new Promise((resolve) => {
    let done = false;
    h._getLatestBlob(field, (v) => { done = true; resolve(v || ''); });
    setTimeout(() => { if (!done) resolve(null); }, 5000);
  });
  const decode = (v) => (v && /%u[0-9A-F]{4}|%3C/i.test(v) ? unescape(v) : v);

  async function ready() {
    for (let i = 0; i < 30; i++) {
      if (window.Campaign && Campaign.handouts && Campaign.players) return true;
      await sleep(1000);
    }
    throw new Error('Campaign 객체가 없다 — 게임 화면(/editor/)이 맞는지, 로딩이 끝났는지 확인');
  }

  function players() {
    return Campaign.players.models.map((p) => ({ id: p.id, name: p.get('displayname') }));
  }

  function list() {
    return Campaign.handouts.models.map((h) => ({
      id: h.id, name: h.get('name'), inplayerjournals: h.get('inplayerjournals'),
      archived: h.get('archived'),
    }));
  }

  async function read(id) {
    const h = Campaign.handouts.get(id);
    if (!h) return null;
    return {
      id, name: h.get('name'), inplayerjournals: h.get('inplayerjournals'),
      avatar: h.get('avatar'), notes: decode(await readBlob(h, 'notes')),
      gmnotes: decode(await readBlob(h, 'gmnotes')),
    };
  }

  // visibleTo: 'gm' | 'all' | [displayname, ...]
  function resolveVisibility(visibleTo) {
    if (!visibleTo || visibleTo === 'gm') return '';
    if (visibleTo === 'all') return 'all';
    const ps = players();
    return visibleTo.map((name) => {
      const p = ps.find((x) => x.name === name);
      if (!p) throw new Error(`플레이어 없음: ${name} (있는 이름: ${ps.map((x) => x.name).join(', ')})`);
      return p.id;
    }).join(',');
  }

  // items: [{key, id?, name, notes, gmnotes, visibleTo, avatar?, archived?}]
  // 반환: [{key, id, action: created|updated|skipped|error, error?}]
  async function upsert(expectedCampaignId, items) {
    await ready();
    if (String(window.campaign_id) !== String(expectedCampaignId)) {
      throw new Error(`열린 게임(${window.campaign_id})이 대상(${expectedCampaignId})과 다르다 — 아무것도 쓰지 않음`);
    }
    const results = [];
    for (const it of items) {
      try {
        const attrs = { name: it.name, inplayerjournals: resolveVisibility(it.visibleTo) };
        if (it.avatar !== undefined) attrs.avatar = it.avatar;
        if (it.archived !== undefined) attrs.archived = it.archived;
        let h = it.id && Campaign.handouts.get(it.id);
        let action = 'updated';
        if (it.id && !h) {
          results.push({ key: it.key, id: it.id, action: 'error', error: '잠금 파일의 id 가 게임에 없다(롤20에서 지워졌나?)' });
          continue;
        }
        if (!h) {
          const dup = Campaign.handouts.models.filter((x) => x.get('name') === it.name);
          if (dup.length) {
            results.push({ key: it.key, action: 'error', error: `같은 이름의 핸드아웃이 이미 있다: ${dup.map((x) => x.id).join(', ')}` });
            continue;
          }
          h = Campaign.handouts.create({ ...attrs, controlledby: '', archived: attrs.archived ?? false });
          action = 'created';
          await sleep(1000);
        } else {
          h.save(attrs);
        }
        h.updateBlobs({ notes: it.notes || '', gmnotes: it.gmnotes || '' });
        await sleep(800);
        const back = await read(h.id);
        const ok = back && back.notes === (it.notes || '') && back.gmnotes === (it.gmnotes || '');
        results.push({ key: it.key, id: h.id, action: ok ? action : 'error', error: ok ? undefined : '되읽은 본문이 다르다' });
      } catch (e) {
        results.push({ key: it.key, id: it.id, action: 'error', error: e.message });
      }
    }
    return results;
  }

  function remove(id) {
    const h = Campaign.handouts.get(id);
    if (!h) return false;
    h.destroy();
    return true;
  }

  return { ready, players, list, read, upsert, remove };
})();
