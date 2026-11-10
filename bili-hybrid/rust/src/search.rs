//! BM25 检索 + 安全高亮（并行）。中文按单字 + 相邻 bigram 切分，ASCII 按词切分。

use crate::error::CoreResult;
use crate::model::Video;
use rayon::prelude::*;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

pub fn tokenize(s: &str) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut ascii = String::new();
    for (i, &ch) in chars.iter().enumerate() {
        if ch.is_ascii_alphanumeric() {
            ascii.push(ch.to_ascii_lowercase());
            continue;
        }
        if !ascii.is_empty() {
            out.push(std::mem::take(&mut ascii));
        }
        if ch.is_whitespace() || ch.is_ascii_punctuation() {
            continue;
        }
        out.push(ch.to_lowercase().collect::<String>());
        if i > 0 {
            let prev = chars[i - 1];
            if !prev.is_ascii_alphanumeric()
                && !prev.is_whitespace()
                && !prev.is_ascii_punctuation()
            {
                out.push(format!("{}{}", prev, ch));
            }
        }
    }
    if !ascii.is_empty() {
        out.push(ascii);
    }
    out
}

fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

/// 先整体转义，再插入 <mark>；输出可安全交给前端内联渲染。
fn highlight(title: &str, query: &str) -> String {
    let escaped = html_escape(title);
    let needle = query.trim();
    if needle.is_empty() {
        return escaped;
    }
    let lower = escaped.to_lowercase();
    let nl = needle.to_lowercase();
    if let Some(pos) = lower.find(&nl) {
        let end = pos + nl.len();
        if escaped.is_char_boundary(pos) && escaped.is_char_boundary(end) {
            return format!(
                "{}<mark>{}</mark>{}",
                &escaped[..pos],
                &escaped[pos..end],
                &escaped[end..]
            );
        }
    }
    escaped
}

pub fn search(videos: &[u8], query: &str, limit: usize) -> CoreResult<Vec<u8>> {
    let vids: Vec<Video> = serde_json::from_slice(videos)?;
    let q = tokenize(query);
    if q.is_empty() {
        let mut v = vids;
        if limit > 0 {
            v.truncate(limit);
        }
        return Ok(serde_json::to_vec(&v)?);
    }

    let docs: Vec<Vec<String>> = vids
        .iter()
        .map(|v| tokenize(&format!("{} {} {}", v.title, v.owner.name, v.tname)))
        .collect();
    let n = docs.len().max(1) as f64;
    let mut df: HashMap<String, usize> = HashMap::new();
    for d in &docs {
        let mut seen = HashSet::new();
        for t in d {
            if seen.insert(t.clone()) {
                *df.entry(t.clone()).or_insert(0) += 1;
            }
        }
    }
    let avgdl = docs.iter().map(|d| d.len() as f64).sum::<f64>() / n;
    let (k1, b) = (1.5_f64, 0.75_f64);
    let q_lower = query.trim().to_lowercase();

    let scored: Vec<(f64, String)> = docs
        .par_iter()
        .zip(vids.par_iter())
        .map(|(d, v)| {
            let dl = d.len() as f64;
            let mut tf: HashMap<&str, usize> = HashMap::new();
            for t in d {
                *tf.entry(t.as_str()).or_insert(0) += 1;
            }
            let mut s = 0.0;
            for qt in &q {
                let f = *tf.get(qt.as_str()).unwrap_or(&0) as f64;
                if f == 0.0 {
                    continue;
                }
                let dfi = *df.get(qt).unwrap_or(&0) as f64;
                let idf = ((n - dfi + 0.5) / (dfi + 0.5) + 1.0).ln().max(0.001);
                s += idf * (f * (k1 + 1.0))
                    / (f + k1 * (1.0 - b + b * dl / avgdl.max(1.0)));
            }
            if !q_lower.is_empty() && v.title.to_lowercase().contains(&q_lower) {
                s += 2.0;
            }
            (s, highlight(&v.title, query))
        })
        .collect();

    let mut pairs: Vec<(usize, f64, String)> = scored
        .into_iter()
        .enumerate()
        .map(|(i, (s, h))| (i, (s * 1e6).round() / 1e6, h))
        .filter(|(_, s, _)| *s > 0.0)
        .collect();
    pairs.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(Ordering::Equal));
    if limit > 0 {
        pairs.truncate(limit);
    }
    let out: Vec<Video> = pairs
        .into_iter()
        .map(|(i, s, h)| {
            let mut v = vids[i].clone();
            v.score = Some(s);
            v.highlight = Some(h);
            v
        })
        .collect();
    Ok(serde_json::to_vec(&out)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenize_mixed() {
        let t = tokenize("Flutter 教程 2026");
        assert!(t.contains(&"flutter".to_string()));
        assert!(t.contains(&"教".to_string()));
        assert!(t.contains(&"教程".to_string()));
    }

    #[test]
    fn highlight_is_escaped() {
        assert_eq!(highlight("A&B", "A"), "<mark>A</mark>&amp;B");
        assert_eq!(highlight("中文标题", "中文"), "<mark>中文</mark>标题");
    }
}
