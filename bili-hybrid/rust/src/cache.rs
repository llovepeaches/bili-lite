//! 进程内并发缓存：TTL + 近似 LRU，Mutex<HashMap> + OnceLock 全局单例。
//! 放在 Rust 侧的价值是命中/淘汰与打分共用同一份内存，跨 Python 线程安全，
//! 且 GIL 释放后多个 Worker 可以并发命中而无需额外的 Redis 往返。

use crate::error::{CoreError, CoreResult};
use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

struct Entry {
    value: Vec<u8>,
    expires: Option<Instant>,
    seq: u64,
}

struct Store {
    map: HashMap<String, Entry>,
    seq: u64,
    capacity: usize,
    hits: u64,
    misses: u64,
}

static STORE: OnceLock<Mutex<Store>> = OnceLock::new();

fn store() -> &'static Mutex<Store> {
    STORE.get_or_init(|| Mutex::new(Store {
        map: HashMap::new(),
        seq: 0,
        capacity: 256,
        hits: 0,
        misses: 0,
    }))
}

fn lock() -> CoreResult<MutexGuard<'static, Store>> {
    store()
        .lock()
        .map_err(|e| CoreError::State(format!("cache lock poisoned: {}", e)))
}

fn purge_expired(s: &mut Store, now: Instant) {
    s.map.retain(|_, e| e.expires.map(|x| x > now).unwrap_or(true));
}

pub fn put(key: &str, value: &[u8], ttl_secs: u64) -> CoreResult<()> {
    let mut s = lock()?;
    s.seq += 1;
    // 先把 seq 拷出来，避免 insert 时对 s.map 的可变借用与 s.seq 的只读借用冲突。
    let seq = s.seq;
    let expires = (ttl_secs > 0).then(|| Instant::now() + Duration::from_secs(ttl_secs));
    s.map.insert(
        key.to_string(),
        Entry {
            value: value.to_vec(),
            expires,
            seq,
        },
    );
    purge_expired(&mut s, Instant::now());
    while s.map.len() > s.capacity {
        let oldest = s
            .map
            .iter()
            .min_by_key(|(_, e)| e.seq)
            .map(|(k, _)| k.clone());
        match oldest {
            Some(k) => {
                s.map.remove(&k);
            }
            None => break,
        }
    }
    Ok(())
}

pub fn get(key: &str) -> CoreResult<Option<Vec<u8>>> {
    let mut s = lock()?;
    let now = Instant::now();
    let expired = s
        .map
        .get(key)
        .map(|e| e.expires.map(|x| x <= now).unwrap_or(false))
        .unwrap_or(false);
    if expired {
        s.map.remove(key);
    }
    // 先取值（结束对 s.map 的不可变借用），再更新计数。
    let value = s.map.get(key).map(|e| e.value.clone());
    match value {
        Some(v) => {
            s.hits += 1;
            Ok(Some(v))
        }
        None => {
            s.misses += 1;
            Ok(None)
        }
    }
}

pub fn stats() -> CoreResult<Vec<u8>> {
    let mut s = lock()?;
    purge_expired(&mut s, Instant::now());
    let out = serde_json::json!({
        "entries": s.map.len(),
        "capacity": s.capacity,
        "hits": s.hits,
        "misses": s.misses,
    });
    Ok(serde_json::to_vec(&out)?)
}

pub fn clear() -> CoreResult<()> {
    let mut s = lock()?;
    s.map.clear();
    Ok(())
}
