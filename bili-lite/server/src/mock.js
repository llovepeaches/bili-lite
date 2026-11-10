'use strict';

/**
 * 离线演示数据。内容取自 B 站公开接口的真实数据快照（见 mock-data.json），
 * 仅在 upstream 不可达 / MOCK_MODE=1 时启用，保证任何环境下 UI 都不会白屏。
 */

const snapshot = require('./mock-data.json');

const allVideos = [
  ...snapshot.feed,
  ...snapshot.popular,
  ...snapshot.rank.list,
  ...snapshot.search.list,
];

function detailFor(bvid) {
  const base =
    snapshot.detail && (!bvid || snapshot.detail.bvid === bvid)
      ? snapshot.detail
      : allVideos.find((v) => v.bvid === bvid) || snapshot.rank.list[0] || snapshot.feed[0];

  return {
    ...base,
    bvid: bvid || base.bvid,
    pages:
      base.pages && base.pages.length
        ? base.pages
        : [
            {
              cid: base.cid,
              page: 1,
              part: base.title,
              duration: base.duration,
              durationText: base.durationText,
            },
          ],
    dynamic: base.dynamic || '',
    tags: base.tags || [],
  };
}

function searchFor(keyword) {
  const kw = (keyword || '').trim().toLowerCase();
  const list = snapshot.search.list;
  if (!kw) return { ...snapshot.search, list };
  const matched = list.filter(
    (v) => v.title.toLowerCase().includes(kw) || v.owner.name.toLowerCase().includes(kw)
  );
  // 关键词命中太少时用全站内容补齐，避免「搜什么都没结果」的演示体验
  const filler = matched.length >= 6 ? [] : allVideos.filter((v) => !matched.includes(v)).slice(0, 8);
  return {
    page: 1,
    pages: 1,
    total: matched.length + filler.length,
    list: [...matched, ...filler],
    keyword,
  };
}

module.exports = {
  snapshotAt: snapshot.snapshotAt,
  feed: () => snapshot.feed,
  rank: () => snapshot.rank,
  popular: () => snapshot.popular,
  search: searchFor,
  detail: detailFor,
  reply: () => snapshot.reply,
  allVideos: () => allVideos,
};
