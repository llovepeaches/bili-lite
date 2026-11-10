//! 热度打分、并行排序与聚合统计（CPU 密集，rayon 并行）。

use crate::error::CoreResult;
use crate::model::Video;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Weights {
    pub view: f64,
    pub danmaku: f64,
    pub reply: f64,
    pub like: f64,
    pub coin: f64,
    pub favorite: f64,
    pub share: f64,
    pub half_life_hours: f64,
    /// 0 表示由 Rust 取系统时间，便于离线快照复现时可显式指定。
    pub now: i64,
}

impl Default for Weights {
    fn default() -> Self {
        Self {
            view: 1.0,
            danmaku: 1.5,
            reply: 3.0,
            like: 4.0,
            coin: 8.0,
            favorite: 6.0,
            share: 5.0,
            half_life_hours: 72.0,
            now: 0,
        }
    }
}

fn now_ts(w: &Weights) -> i64 {
    if w.now > 0 {
        w.now
    } else {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0)
    }
}

/// 互动加权取对数压缩量级，再乘半衰期时间衰减。
pub fn score(v: &Video, w: &Weights, now: i64) -> f64 {
    let s = &v.stat;
    let raw = s.view as f64 * w.view
        + s.danmaku as f64 * w.danmaku
        + s.reply as f64 * w.reply
        + s.like as f64 * w.like
        + s.coin as f64 * w.coin
        + s.favorite as f64 * w.favorite
        + s.share as f64 * w.share;
    let engagement = raw.max(0.0).ln_1p();
    let age_h = (now.saturating_sub(v.pubdate).max(0) as f64) / 3600.0;
    let decay = 0.5f64.powf(age_h / w.half_life_hours.max(1.0));
    engagement * decay
}

pub fn rank(videos: &[u8], weights: &[u8], limit: usize) -> CoreResult<Vec<u8>> {
    let mut vids: Vec<Video> = serde_json::from_slice(videos)?;
    let w: Weights = if weights.is_empty() {
        Weights::default()
    } else {
        serde_json::from_slice(weights)?
    };
    let now = now_ts(&w);
    let scores: Vec<f64> = vids.par_iter().map(|v| score(v, &w, now)).collect();
    for (v, s) in vids.iter_mut().zip(scores) {
        v.score = Some((s * 1e6).round() / 1e6);
    }
    vids.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(Ordering::Equal)
    });
    if limit > 0 {
        vids.truncate(limit);
    }
    Ok(serde_json::to_vec(&vids)?)
}

pub fn aggregate(videos: &[u8]) -> CoreResult<Vec<u8>> {
    let vids: Vec<Video> = serde_json::from_slice(videos)?;
    let total_view: u64 = vids.iter().map(|v| v.stat.view).sum();
    let total_like: u64 = vids.iter().map(|v| v.stat.like).sum();
    let total_duration: u64 = vids.iter().map(|v| v.duration).sum();
    let mut by_source: HashMap<String, usize> = HashMap::new();
    for v in &vids {
        *by_source.entry(v.source.clone()).or_insert(0) += 1;
    }
    let out = serde_json::json!({
        "count": vids.len(),
        "totalView": total_view,
        "totalLike": total_like,
        "totalDuration": total_duration,
        "avgDuration": if vids.is_empty() { 0 } else { total_duration / vids.len() as u64 },
        "bySource": by_source,
    });
    Ok(serde_json::to_vec(&out)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn video(pubdate: i64, view: u64) -> Video {
        serde_json::from_value(serde_json::json!({
            "aid":"1","bvid":"BV1","cid":"1","title":"t","cover":"",
            "duration":10,"durationText":"00:10",
            "owner":{"mid":"1","name":"n","face":""},
            "stat":{"view":view,"danmaku":0,"reply":0,"like":0,"coin":0,"favorite":0,"share":0},
            "pubdate":pubdate,"desc":"","tname":"","reason":"","source":"feed"
        }))
        .unwrap()
    }

    #[test]
    fn newer_scores_higher_with_decay() {
        let w = Weights::default();
        let now = 1_700_000_000_i64;
        let fresh = score(&video(now - 3600, 1000), &w, now);
        let old = score(&video(now - 3600 * 24 * 30, 1000), &w, now);
        assert!(fresh > old, "fresh={} old={}", fresh, old);
    }

    #[test]
    fn rank_sorts_desc() {
        let now = 1_700_000_000_i64;
        let vids = vec![video(now, 10), video(now, 100000), video(now, 1000)];
        let raw = serde_json::to_vec(&vids).unwrap();
        let w = serde_json::to_vec(&Weights { now, ..Weights::default() }).unwrap();
        let out = rank(&raw, &w, 2).unwrap();
        let got: Vec<Video> = serde_json::from_slice(&out).unwrap();
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].stat.view, 100000);
    }
}
