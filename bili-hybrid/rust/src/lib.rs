//! Bili 纯 Rust 计算内核。
//!
//! 这一层**完全不知道 Python 的存在**：只依赖 serde / serde_json / rayon，
//! 因此可以独立 `cargo test -p bili-core`，也可以被 PyO3 之外的绑定
//! （C FFI、WASM、CLI）复用。语言绑定单独放在 `rust-py` crate。

pub mod cache;
pub mod error;
pub mod model;
pub mod normalize;
pub mod rank;
pub mod search;
