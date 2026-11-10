//! 内部强类型模型。
//!
//! 边界策略：**输入宽松、输出严格**。上游 B 站接口有多套互不兼容的字段命名，
//! 归一化层用 serde_json::Value 动态提取；一旦进入内核，全部是编译期检查的强类型，
//! 且序列化时统一转 camelCase，作为跨语言与前后端共享的唯一数据契约。

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Owner {
    pub mid: String,
    pub name: String,
    pub face: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Stat {
    pub view: u64,
    pub danmaku: u64,
    pub reply: u64,
    pub like: u64,
    pub coin: u64,
    pub favorite: u64,
    pub share: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Video {
    pub aid: String,
    pub bvid: String,
    pub cid: String,
    pub title: String,
    pub cover: String,
    pub duration: u64,
    pub duration_text: String,
    pub owner: Owner,
    pub stat: Stat,
    pub pubdate: i64,
    pub desc: String,
    pub tname: String,
    pub reason: String,
    pub source: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub score: Option<f64>,
    /// 已由 Rust 做过 HTML 转义的安全高亮片段，前端可安全内联渲染。
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub highlight: Option<String>,
}
