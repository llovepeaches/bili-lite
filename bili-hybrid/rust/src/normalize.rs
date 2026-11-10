//! 上游多 schema → 内部统一模型。
//!
//! B 站推荐 / 排行榜 / 热门 / 搜索四套接口的字段命名互不相同：
//! 推荐用 pic + owner{mid,name,face} + stat{view,...} + rcmd_reason{content}；
//! 搜索用 pic + author + mid + play + review + 扁平数值字段；
//! 排行榜多一层 score，热门又用 rcmd_reason。这里全部收敛到单一的 Video。
//! 输入用 Value 动态提取（上游 schema 不可控），输出是编译期检查的强类型。

use crate::error::{CoreError, CoreResult};
use crate::model::{Owner, Stat, Video};
use serde_json::Value;
use std::collections::HashSet;

/// 按优先级取第一个存在且非 null 的字段。
fn pick<'a>(obj: &'a Value, keys: &[&str]) -> Option<&'a Value> {
    for k in keys {
        if let Some(v) = obj.get(*k) {
            if !v.is_null() {
                return Some(v);
            }
        }
    }
    None
}

fn as_str(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        _ => String::new(),
    }
}

fn as_u64(v: Option<&Value>) -> u64 {
    match v {
        Some(Value::Number(n)) => n
            .as_u64()
            .or_else(|| n.as_f64().map(|x| x.max(0.0) as u64))
            .unwrap_or(0),
        Some(Value::String(s)) => s.parse::<f64>().map(|x| x.max(0.0) as u64).unwrap_or(0),
        _ => 0,
    }
}

fn as_i64(v: Option<&Value>) -> i64 {
    match v {
        Some(Value::Number(n)) => n.as_i64().unwrap_or(0),
        Some(Value::String(s)) => s.parse::<i64>().unwrap_or(0),
        _ => 0,
    }
}

/// 去掉搜索接口塞进标题的 <em class="keyword">…</em> 等标签，并压平空白。
pub fn clean_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_tag = false;
    for ch in s.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn cover(v: Option<&Value>) -> String {
    let s = as_str(v);
    if s.starts_with("//") {
        format!("https:{}", s)
    } else if s.starts_with("http://") {
        s.replacen("http://", "https://", 1)
    } else {
        s
    }
}

pub fn duration_text(sec: u64) -> String {
    let h = sec / 3600;
    let m = (sec % 3600) / 60;
    let s = sec % 60;
    if h > 0 {
        format!("{:02}:{:02}:{:02}", h, m, s)
    } else {
        format!("{:02}:{:02}", m, s)
    }
}

pub fn parse_clock(s: &str) -> u64 {
    let parts: Vec<u64> = s
        .split(':')
        .filter_map(|x| x.trim().parse::<u64>().ok())
        .collect();
    match parts.len() {
        2 => parts[0] * 60 + parts[1],
        3 => parts[0] * 3600 + parts[1] * 60 + parts[2],
        _ => 0,
    }
}

fn duration(obj: &Value) -> u64 {
    match pick(obj, &["duration"]) {
        Some(Value::Number(n)) => return n.as_u64().unwrap_or(0),
        Some(Value::String(s)) if s.contains(':') => return parse_clock(s),
        _ => {}
    }
    let txt = as_str(pick(obj, &["durationText", "duration_text", "duration_str"]));
    parse_clock(&txt)
}

fn owner(obj: &Value) -> Owner {
    if let Some(Value::Object(o)) = pick(obj, &["owner", "authorInfo", "upper"]) {
        return Owner {
            mid: as_str(o.get("mid")),
            name: clean_text(&as_str(o.get("name"))),
            face: cover(o.get("face")),
        };
    }
    // 搜索接口：author / mid / face 是扁平字段
    Owner {
        mid: as_str(pick(obj, &["mid", "authorId"])),
        name: clean_text(&as_str(pick(obj, &["author", "nickname", "uname"]))),
        face: cover(pick(obj, &["face", "upic"])),
    }
}

fn stat(obj: &Value) -> Stat {
    if let Some(Value::Object(o)) = pick(obj, &["stat", "stats", "counter"]) {
        return Stat {
            view: as_u64(o.get("view")),
            danmaku: as_u64(o.get("danmaku")),
            reply: as_u64(o.get("reply")),
            like: as_u64(o.get("like")),
            coin: as_u64(o.get("coin")),
            favorite: as_u64(o.get("favorite")),
            share: as_u64(o.get("share")),
        };
    }
    Stat {
        view: as_u64(pick(obj, &["play", "view"])),
        danmaku: as_u64(pick(obj, &["danmaku", "videoReview", "dm"])),
        reply: as_u64(pick(obj, &["review", "reply"])),
        like: as_u64(pick(obj, &["like", "likes"])),
        coin: as_u64(pick(obj, &["coin", "coins"])),
        favorite: as_u64(pick(obj, &["favorite", "favorites", "fav"])),
        share: as_u64(pick(obj, &["share"])),
    }
}

fn reason(obj: &Value) -> String {
    if let Some(Value::Object(o)) = obj.get("rcmd_reason") {
        let c = clean_text(&as_str(o.get("content")));
        if !c.is_empty() {
            return c;
        }
    }
    clean_text(&as_str(pick(obj, &["reason", "rcmdReason", "badgeText"])))
}

fn one(source: &str, obj: &Value) -> Video {
    let dur = duration(obj);
    Video {
        aid: as_str(pick(obj, &["aid", "id", "avid"])),
        bvid: as_str(pick(obj, &["bvid", "bvId"])),
        cid: as_str(pick(obj, &["cid", "firstCid"])),
        title: clean_text(&as_str(pick(obj, &["title"]))),
        cover: cover(pick(obj, &["cover", "pic", "coverUrl"])),
        duration: dur,
        duration_text: duration_text(dur),
        owner: owner(obj),
        stat: stat(obj),
        pubdate: as_i64(pick(obj, &["pubdate", "pubDate", "created", "ctime"])),
        desc: clean_text(&as_str(pick(obj, &["desc", "description", "intro"]))),
        tname: clean_text(&as_str(pick(obj, &["tname", "typename", "tag", "category"]))),
        reason: reason(obj),
        source: source.to_string(),
        score: None,
        highlight: None,
    }
}

pub fn normalize(source: &str, raw: &[u8]) -> CoreResult<Vec<u8>> {
    if raw.is_empty() {
        return Err(CoreError::InvalidInput("empty payload".into()));
    }
    let root: Value = serde_json::from_slice(raw)?;
    let list: Vec<&Value> = match &root {
        Value::Array(a) => a.iter().collect(),
        Value::Object(_) => match pick(&root, &["list", "items", "result", "data"]) {
            Some(Value::Array(a)) => a.iter().collect(),
            Some(Value::Object(o)) => match o
                .get("list")
                .or_else(|| o.get("items"))
                .or_else(|| o.get("result"))
            {
                Some(Value::Array(a)) => a.iter().collect(),
                _ => Vec::new(),
            },
            _ => Vec::new(),
        },
        _ => return Err(CoreError::InvalidInput("payload must be array or object".into())),
    };
    let videos: Vec<Video> = list.iter().map(|v| one(source, *v)).collect();
    Ok(serde_json::to_vec(&videos)?)
}

/// 按 bvid 去重（缺失时退化为 aid|title），保留首次出现顺序。
pub fn dedupe(videos: &[u8]) -> CoreResult<Vec<u8>> {
    let vids: Vec<Video> = serde_json::from_slice(videos)?;
    let mut seen = HashSet::new();
    let out: Vec<Video> = vids
        .into_iter()
        .filter(|v| {
            let key = if !v.bvid.is_empty() {
                v.bvid.clone()
            } else {
                format!("{}|{}", v.aid, v.title)
            };
            seen.insert(key)
        })
        .collect();
    Ok(serde_json::to_vec(&out)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_search_flat_schema() {
        // 含中文不能用 br#""# 字节串，改用普通 raw string 再取 UTF-8 字节。
        let raw = r#"[{"bvid":"BV1","pic":"//i0.hdslb.com/a.jpg","title":"Rust <em>教程</em>","author":"UP君","mid":42,"play":1000,"pubdate":100}]"#.as_bytes();
        let out = normalize("search", raw).unwrap();
        let v: Vec<Value> = serde_json::from_slice(&out).unwrap();
        assert_eq!(v[0]["title"], "Rust 教程");
        assert_eq!(v[0]["owner"]["name"], "UP君");
        assert_eq!(v[0]["stat"]["view"], 1000);
        assert!(v[0]["cover"].as_str().unwrap().starts_with("https://"));
        assert_eq!(v[0]["source"], "search");
    }

    #[test]
    fn nested_object_payload() {
        let raw = br#"{"data":{"list":[{"bvid":"BV2","title":"A","duration":"01:14","stat":{"view":7}}]}}"#;
        let out = normalize("feed", raw).unwrap();
        let v: Vec<Value> = serde_json::from_slice(&out).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["duration"], 74);
        assert_eq!(v[0]["durationText"], "01:14");
    }

    #[test]
    fn clock_and_dedupe() {
        assert_eq!(duration_text(74), "01:14");
        assert_eq!(parse_clock("1:02:03"), 3723);
        let raw = br#"[{"bvid":"BV1","title":"a"},{"bvid":"BV1","title":"b"},{"bvid":"BV2","title":"c"}]"#;
        let v = normalize("feed", raw).unwrap();
        let d = dedupe(&v).unwrap();
        let out: Vec<Value> = serde_json::from_slice(&d).unwrap();
        assert_eq!(out.len(), 2);
    }
}
