//! PyO3 导出层 —— Rust 与 Python 之间**唯一**的边界。
//!
//! 本 crate 只有胶水，没有任何业务逻辑（逻辑全在 `bili-core`）。
//! 设计原则：
//! 1. **批量语义**：每个函数一次处理整批数据，N 条视频只跨界 1 次；
//! 2. **字节契约**：入参 `&[u8]` / 出参 `Vec<u8>` 都是 JSON 字节，避免逐字段转换；
//! 3. **释放 GIL**：`py.allow_threads` 内只持有 Rust 所有权数据，rayon 可真正并行，
//!    FastAPI 的其他线程也不会被计算阻塞；
//! 4. **单一错误通道**：CoreError → PyValueError(结构化 JSON) → Python 侧 BiliCoreError。

use bili_core::{cache, error, normalize, rank, search};
use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use pyo3::PyErr;

fn py_err(e: error::CoreError) -> PyErr {
    PyValueError::new_err(e.payload())
}

fn detach<T, F>(py: Python<'_>, f: F) -> PyResult<T>
where
    F: FnOnce() -> error::CoreResult<T> + Send,
    T: Send,
{
    py.allow_threads(f).map_err(py_err)
}

/// 把某套上游原始 JSON 归一成统一 Video 列表。source ∈ feed|rank|popular|search|detail。
#[pyfunction]
fn normalize_batch(py: Python<'_>, source: &str, raw: &[u8]) -> PyResult<Vec<u8>> {
    let source = source.to_string();
    let raw = raw.to_vec();
    detach(py, move || normalize::normalize(&source, &raw))
}

/// 按权重并行打分并排序；weights 为空则用默认权重，limit=0 表示不截断。
#[pyfunction]
fn rank_videos(
    py: Python<'_>,
    videos: &[u8],
    weights: &[u8],
    limit: usize,
) -> PyResult<Vec<u8>> {
    let videos = videos.to_vec();
    let weights = weights.to_vec();
    detach(py, move || rank::rank(&videos, &weights, limit))
}

/// BM25 检索，返回带 score 与已 HTML 转义 highlight 的结果。
#[pyfunction]
fn search_videos(
    py: Python<'_>,
    videos: &[u8],
    query: &str,
    limit: usize,
) -> PyResult<Vec<u8>> {
    let videos = videos.to_vec();
    let query = query.to_string();
    detach(py, move || search::search(&videos, &query, limit))
}

#[pyfunction]
fn dedupe_videos(py: Python<'_>, videos: &[u8]) -> PyResult<Vec<u8>> {
    let videos = videos.to_vec();
    detach(py, move || normalize::dedupe(&videos))
}

#[pyfunction]
fn aggregate_videos(py: Python<'_>, videos: &[u8]) -> PyResult<Vec<u8>> {
    let videos = videos.to_vec();
    detach(py, move || rank::aggregate(&videos))
}

#[pyfunction]
fn cache_get(py: Python<'_>, key: &str) -> PyResult<Option<Vec<u8>>> {
    let key = key.to_string();
    detach(py, move || cache::get(&key))
}

#[pyfunction]
fn cache_put(py: Python<'_>, key: &str, value: &[u8], ttl_secs: u64) -> PyResult<()> {
    let key = key.to_string();
    let value = value.to_vec();
    detach(py, move || cache::put(&key, &value, ttl_secs))
}

#[pyfunction]
fn cache_stats(py: Python<'_>) -> PyResult<Vec<u8>> {
    detach(py, cache::stats)
}

#[pyfunction]
fn cache_clear(py: Python<'_>) -> PyResult<()> {
    detach(py, cache::clear)
}

#[pyfunction]
fn core_info() -> String {
    serde_json::json!({
        "version": env!("CARGO_PKG_VERSION"),
        "engine": "rust",
        "bindings": "pyo3",
        "parallel": true,
        "kernel": "bili-core",
        "capabilities": [
            "normalize_batch", "rank_videos", "search_videos",
            "dedupe_videos", "aggregate_videos", "cache"
        ],
    })
    .to_string()
}

#[pymodule]
fn _native(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(normalize_batch, m)?)?;
    m.add_function(wrap_pyfunction!(rank_videos, m)?)?;
    m.add_function(wrap_pyfunction!(search_videos, m)?)?;
    m.add_function(wrap_pyfunction!(dedupe_videos, m)?)?;
    m.add_function(wrap_pyfunction!(aggregate_videos, m)?)?;
    m.add_function(wrap_pyfunction!(cache_get, m)?)?;
    m.add_function(wrap_pyfunction!(cache_put, m)?)?;
    m.add_function(wrap_pyfunction!(cache_stats, m)?)?;
    m.add_function(wrap_pyfunction!(cache_clear, m)?)?;
    m.add_function(wrap_pyfunction!(core_info, m)?)?;
    m.add("__version__", env!("CARGO_PKG_VERSION"))?;
    Ok(())
}
