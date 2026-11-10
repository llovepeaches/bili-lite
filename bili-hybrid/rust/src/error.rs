//! 内核错误类型。刻意不依赖 pyo3 —— 错误到 Python 异常的映射属于绑定层职责。

use serde_json::json;

pub type CoreResult<T> = Result<T, CoreError>;

#[derive(Debug, Clone)]
pub enum CoreError {
    InvalidJson(String),
    InvalidInput(String),
    State(String),
}

impl CoreError {
    pub fn code(&self) -> &'static str {
        match self {
            CoreError::InvalidJson(_) => "INVALID_JSON",
            CoreError::InvalidInput(_) => "INVALID_INPUT",
            CoreError::State(_) => "STATE_ERROR",
        }
    }

    /// 供绑定层序列化的结构化载荷。
    pub fn payload(&self) -> String {
        json!({ "code": self.code(), "message": self.to_string() }).to_string()
    }
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreError::InvalidJson(m)
            | CoreError::InvalidInput(m)
            | CoreError::State(m) => write!(f, "{}", m),
        }
    }
}

impl From<serde_json::Error> for CoreError {
    fn from(e: serde_json::Error) -> Self {
        CoreError::InvalidJson(e.to_string())
    }
}
