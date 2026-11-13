use futures_util::{StreamExt, TryStreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlparser::{
    ast::Statement,
    dialect::{MySqlDialect, PostgreSqlDialect},
    keywords::Keyword,
    parser::Parser,
    tokenizer::{Token, Tokenizer},
};
use sqlx::{Acquire, Column, ConnectOptions, Row, TypeInfo, ValueRef};
use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::RwLock;

const ROW_LIMIT: usize = 500;
const CELL_LIMIT: usize = 65_536;
const BYTE_LIMIT: usize = 8 * 1024 * 1024;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    kind: String,
    host: String,
    port: u16,
    username: String,
    password: String,
    database: String,
    tls: bool,
    endpoint: String,
    api_key: String,
}
#[derive(Clone)]
enum Session {
    Mysql(sqlx::MySqlPool),
    Pg(sqlx::PgPool),
    Es {
        client: reqwest::Client,
        base: url::Url,
        username: String,
        password: String,
        api_key: String,
    },
    Redis(redis::aio::MultiplexedConnection),
}
#[derive(Default)]
struct AppState {
    sessions: RwLock<HashMap<String, Arc<Session>>>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Connected {
    id: String,
    elapsed_ms: u128,
}
#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
struct Output {
    columns: Vec<String>,
    rows: Vec<Vec<Value>>,
    elapsed_ms: u128,
    truncated: bool,
    note: String,
    next_cursor: Option<String>,
}
#[derive(Deserialize)]
struct Request {
    id: String,
    action: String,
    text: String,
    target: String,
    cursor: String,
}

fn clipped(bytes: &[u8]) -> Value {
    if bytes.len() > CELL_LIMIT {
        return Value::String(format!(
            "{}… [展示已截断]",
            String::from_utf8_lossy(&bytes[..CELL_LIMIT])
        ));
    }
    match std::str::from_utf8(bytes) {
        Ok(s) => Value::String(s.to_owned()),
        Err(_) => Value::String(format!("[二进制 {} bytes]", bytes.len())),
    }
}
fn query_error(e: sqlx::Error) -> String {
    match e {
        sqlx::Error::Database(ref db) => format!(
            "数据库执行失败（代码 {}）。请检查语法、权限及数据库版本。",
            db.code().unwrap_or_default()
        ),
        _ => "数据库请求失败，请检查连接状态。".into(),
    }
}
fn validate_sql(kind: &str, sql: &str) -> Result<(), String> {
    if sql.len() > 128 * 1024 {
        return Err("SQL 超过 128 KiB。".into());
    }
    let statements = if kind == "mysql" {
        Parser::parse_sql(&MySqlDialect {}, sql)
    } else {
        Parser::parse_sql(&PostgreSqlDialect {}, sql)
    }
    .map_err(|_| "暂时无法解析这条 SQL；第一版仅支持单条查询。".to_string())?;
    let tokens = if kind == "mysql" {
        Tokenizer::new(&MySqlDialect {}, sql).tokenize()
    } else {
        Tokenizer::new(&PostgreSqlDialect {}, sql).tokenize()
    }
    .map_err(|_| "SQL 分词失败。".to_string())?;
    if tokens
        .iter()
        .any(|token| matches!(token, Token::Word(word) if word.keyword == Keyword::INTO))
    {
        return Err("查询模式不支持 SELECT INTO / INTO OUTFILE。".into());
    }
    if statements.len() != 1 || !matches!(&statements[0], Statement::Query(_)) {
        return Err("第一版仅执行单条 SELECT / WITH 查询，修改和事务操作稍后开放。".into());
    }
    Ok(())
}
fn quote_identifier(s: &str, mysql: bool) -> String {
    let q = if mysql { '`' } else { '"' };
    format!("{q}{}{q}", s.replace(q, &format!("{q}{q}")))
}

async fn open_session(config: Config) -> Result<Session, String> {
    let result = tokio::time::timeout(Duration::from_secs(12), async {
        let session = match config.kind.as_str() {
            "mysql" => {
                use sqlx::mysql::{MySqlConnectOptions, MySqlPoolOptions, MySqlSslMode};
                let mut options = MySqlConnectOptions::new()
                    .host(&config.host)
                    .port(config.port)
                    .username(&config.username)
                    .ssl_mode(if config.tls {
                        MySqlSslMode::VerifyIdentity
                    } else {
                        MySqlSslMode::Disabled
                    });
                if !config.password.is_empty() {
                    options = options.password(&config.password);
                }
                if !config.database.is_empty() {
                    options = options.database(&config.database);
                }
                options = options.disable_statement_logging();
                let pool = MySqlPoolOptions::new()
                    .max_connections(2)
                    .acquire_timeout(Duration::from_secs(8))
                    .idle_timeout(Duration::from_secs(60))
                    .connect_with(options)
                    .await
                    .map_err(|_| "MySQL 连接失败：请检查地址、账号、TLS 和网络。")?;
                Session::Mysql(pool)
            }
            "pg" => {
                use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
                let mut options = PgConnectOptions::new()
                    .host(&config.host)
                    .port(config.port)
                    .username(&config.username)
                    .ssl_mode(if config.tls {
                        PgSslMode::VerifyFull
                    } else {
                        PgSslMode::Disable
                    });
                if !config.password.is_empty() {
                    options = options.password(&config.password);
                }
                if !config.database.is_empty() {
                    options = options.database(&config.database);
                }
                options = options.disable_statement_logging();
                let pool = PgPoolOptions::new()
                    .max_connections(2)
                    .acquire_timeout(Duration::from_secs(8))
                    .idle_timeout(Duration::from_secs(60))
                    .connect_with(options)
                    .await
                    .map_err(|_| "PostgreSQL 连接失败：请检查地址、账号、TLS 和网络。")?;
                Session::Pg(pool)
            }
            "es" => {
                let base = url::Url::parse(&config.endpoint).map_err(|_| "ES 地址格式错误。")?;
                if !["http", "https"].contains(&base.scheme())
                    || base.host_str().is_none()
                    || !base.username().is_empty()
                    || base.password().is_some()
                    || base.query().is_some()
                    || base.fragment().is_some()
                {
                    return Err("ES 地址仅允许 http(s) 地址，账号和密钥请在独立字段填写。".into());
                }
                let client = reqwest::Client::builder()
                    .timeout(Duration::from_secs(15))
                    .redirect(reqwest::redirect::Policy::none())
                    .build()
                    .map_err(|_| "HTTP 客户端初始化失败。")?;
                let session = Session::Es {
                    client,
                    base,
                    username: config.username,
                    password: config.password,
                    api_key: config.api_key,
                };
                es_request(&session, &[], None).await?;
                session
            }
            "redis" => {
                let db = if config.database.is_empty() {
                    0
                } else {
                    config
                        .database
                        .parse::<u32>()
                        .map_err(|_| "Redis DB 必须是非负整数。")?
                };
                let info = redis::ConnectionInfo {
                    addr: if config.tls {
                        redis::ConnectionAddr::TcpTls {
                            host: config.host,
                            port: config.port,
                            insecure: false,
                            tls_params: None,
                        }
                    } else {
                        redis::ConnectionAddr::Tcp(config.host, config.port)
                    },
                    redis: redis::RedisConnectionInfo {
                        db: db as i64,
                        username: if config.username.is_empty() {
                            None
                        } else {
                            Some(config.username)
                        },
                        password: if config.password.is_empty() {
                            None
                        } else {
                            Some(config.password)
                        },
                        ..Default::default()
                    },
                };
                let client = redis::Client::open(info).map_err(|_| "Redis 连接配置错误。")?;
                let mut connection = client
                    .get_multiplexed_async_connection()
                    .await
                    .map_err(|_| "Redis 连接失败：请检查地址、账号、TLS 和网络。")?;
                let _: String = redis::cmd("PING")
                    .query_async(&mut connection)
                    .await
                    .map_err(|_| "Redis PING 失败。")?;
                Session::Redis(connection)
            }
            _ => return Err("不支持的连接类型。".into()),
        };
        Ok::<_, String>(session)
    })
    .await
    .map_err(|_| "连接超时（12 秒）。".to_string())??;
    Ok(result)
}

async fn connect(config: Config, state: &AppState) -> Result<Connected, String> {
    let started = Instant::now();
    let result = open_session(config).await?;
    let id = uuid::Uuid::new_v4().to_string();
    state
        .sessions
        .write()
        .await
        .insert(id.clone(), Arc::new(result));
    Ok(Connected {
        id,
        elapsed_ms: started.elapsed().as_millis(),
    })
}

async fn disconnect(id: String, state: &AppState) -> Result<(), String> {
    let session = state.sessions.write().await.remove(&id);
    if let Some(s) = session {
        match s.as_ref() {
            Session::Mysql(p) => p.close().await,
            Session::Pg(p) => p.close().await,
            _ => {}
        }
    }
    Ok(())
}

async fn es_request(
    session: &Session,
    segments: &[&str],
    body: Option<Value>,
) -> Result<Value, String> {
    let Session::Es {
        client,
        base,
        username,
        password,
        api_key,
    } = session
    else {
        return Err("连接类型不匹配。".into());
    };
    let mut url = base.clone();
    {
        let mut path = url.path_segments_mut().map_err(|_| "ES 地址格式错误。")?;
        path.pop_if_empty();
        for segment in segments {
            path.push(segment);
        }
    }
    if segments == ["_cat", "indices"] {
        url.query_pairs_mut()
            .append_pair("format", "json")
            .append_pair("h", "index,health,docs.count,store.size");
    }
    let mut request = if let Some(body) = body {
        client.post(url).json(&body)
    } else {
        client.get(url)
    };
    if !api_key.is_empty() {
        request = request.header("Authorization", format!("ApiKey {api_key}"));
    } else if !username.is_empty() {
        request = request.basic_auth(username, Some(password));
    }
    let response = request
        .send()
        .await
        .map_err(|_| "ES 网络请求失败。请检查连接与 TLS。")?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "ES 返回 HTTP {}。请检查权限、索引和查询。",
            status.as_u16()
        ));
    }
    let mut stream = response.bytes_stream();
    let mut bytes = Vec::new();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| "ES 响应读取失败。")?;
        if bytes.len() + chunk.len() > BYTE_LIMIT {
            return Err("ES 响应超过 8 MiB，请减少 size 或使用 _source 筛选。".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| "ES 返回了非 JSON 内容。".into())
}

macro_rules! read_rows {
    ($pool:expr, $sql:expr, $mysql:expr, $decode:expr) => {{
        let mut connection = $pool.acquire().await.map_err(query_error)?;
        if $mysql {
            sqlx::query("SET SESSION TRANSACTION READ ONLY")
                .execute(&mut *connection)
                .await
                .map_err(query_error)?;
            sqlx::query("SET SESSION MAX_EXECUTION_TIME = 15000")
                .execute(&mut *connection)
                .await
                .map_err(query_error)?;
        }
        let mut tx = connection.begin().await.map_err(query_error)?;
        if !$mysql {
            sqlx::query("SET TRANSACTION READ ONLY")
                .execute(&mut *tx)
                .await
                .map_err(query_error)?;
            sqlx::query("SET LOCAL statement_timeout = '15s'")
                .execute(&mut *tx)
                .await
                .map_err(query_error)?;
        }
        let mut output = Output::default();
        let mut bytes = 0usize;
        {
            let mut stream = sqlx::raw_sql($sql).fetch(&mut *tx);
            while let Some(row) = stream.try_next().await.map_err(query_error)? {
                if output.rows.len() >= ROW_LIMIT {
                    output.truncated = true;
                    break;
                }
                if output.columns.is_empty() {
                    output.columns = row.columns().iter().map(|c| c.name().to_string()).collect();
                }
                let mut values = Vec::new();
                for i in 0..row.len() {
                    let raw = row.try_get_raw(i).map_err(query_error)?;
                    let value = if raw.is_null() {
                        Value::Null
                    } else {
                        match ($decode)(raw) {
                            Ok(b) => {
                                if b.len() > CELL_LIMIT {
                                    output.truncated = true;
                                }
                                clipped(&b)
                            }
                            Err(_) => {
                                Value::String(format!("[{}]", row.column(i).type_info().name()))
                            }
                        }
                    };
                    bytes += value.to_string().len();
                    values.push(value);
                }
                if bytes > BYTE_LIMIT {
                    output.truncated = true;
                    break;
                }
                output.rows.push(values);
            }
        }
        tx.rollback().await.map_err(query_error)?;
        output.note = "只读事务 · 最多 500 行 · SQL 数值以文本保留精度".into();
        Ok::<_, String>(output)
    }};
}

async fn execute(session: &Session, request: &Request) -> Result<Output, String> {
    match session {
        Session::Mysql(_) | Session::Pg(_) => {
            let mysql = matches!(session, Session::Mysql(_));
            let sql = match request.action.as_str() {
                "catalog" => {
                    if mysql {
                        "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY table_name LIMIT 500".to_string()
                    } else {
                        "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY table_schema, table_name LIMIT 500".to_string()
                    }
                }
                "preview" => {
                    let parts: Vec<String> =
                        serde_json::from_str(&request.target).map_err(|_| "表标识无效。")?;
                    if parts.len() != 2 {
                        return Err("表标识无效。".into());
                    }
                    format!(
                        "SELECT * FROM {}.{} LIMIT 100",
                        quote_identifier(&parts[0], mysql),
                        quote_identifier(&parts[1], mysql)
                    )
                }
                "query" => {
                    validate_sql(if mysql { "mysql" } else { "pg" }, &request.text)?;
                    request.text.clone()
                }
                _ => return Err("不支持的 SQL 操作。".into()),
            };
            match session {
                Session::Mysql(pool) => {
                    read_rows!(pool, &sql, true, |raw| <Vec<u8> as sqlx::Decode<
                        sqlx::MySql,
                    >>::decode(raw))
                }
                Session::Pg(pool) => {
                    read_rows!(pool, &sql, false, |raw: sqlx::postgres::PgValueRef<'_>| raw
                        .as_bytes()
                        .map(|b| b.to_vec()))
                }
                _ => unreachable!(),
            }
        }
        Session::Es { .. } => match request.action.as_str() {
            "catalog" => {
                let value = es_request(session, &["_cat", "indices"], None).await?;
                let items = value.as_array().ok_or("ES 索引列表格式错误。")?;
                Ok(Output {
                    columns: vec![
                        "index".into(),
                        "health".into(),
                        "docs.count".into(),
                        "store.size".into(),
                    ],
                    rows: items
                        .iter()
                        .take(ROW_LIMIT)
                        .map(|v| {
                            vec![
                                v["index"].clone(),
                                v["health"].clone(),
                                v["docs.count"].clone(),
                                v["store.size"].clone(),
                            ]
                        })
                        .collect(),
                    truncated: items.len() > ROW_LIMIT,
                    note: "按需读取索引列表 · 最多展示 500 项".into(),
                    ..Default::default()
                })
            }
            "query" | "preview" => {
                if request.target.is_empty() || request.target.contains('/') {
                    return Err("请填写索引名或索引模式。".into());
                }
                let mut body: Value = if request.action == "preview" {
                    json!({"query":{"match_all":{}}})
                } else {
                    serde_json::from_str(&request.text).map_err(|_| "查询体不是有效 JSON。")?
                };
                let obj = body.as_object_mut().ok_or("查询体必须是 JSON 对象。")?;
                let size = obj
                    .get("size")
                    .and_then(Value::as_u64)
                    .unwrap_or(100)
                    .min(500);
                obj.insert("size".into(), json!(size));
                let value = es_request(session, &[&request.target, "_search"], Some(body)).await?;
                let hits = value
                    .pointer("/hits/hits")
                    .and_then(Value::as_array)
                    .ok_or("ES 响应中缺少 hits。")?;
                Ok(Output {
                    columns: vec!["_index".into(), "_id".into(), "_source / fields".into()],
                    rows: hits
                        .iter()
                        .map(|h| {
                            vec![
                                h["_index"].clone(),
                                h["_id"].clone(),
                                h.get("_source")
                                    .or_else(|| h.get("fields"))
                                    .cloned()
                                    .unwrap_or(Value::Null),
                            ]
                        })
                        .collect(),
                    note: format!(
                        "最多 500 条 · ES took {} ms · size {} · 结果可能仅为部分匹配",
                        value["took"], size
                    ),
                    ..Default::default()
                })
            }
            _ => Err("不支持的 ES 操作。".into()),
        },
        Session::Redis(connection) => {
            let mut conn = connection.clone();
            match request.action.as_str() {
                "catalog" | "query" => {
                    let cursor = request
                        .cursor
                        .parse::<u64>()
                        .map_err(|_| "SCAN 游标无效。")?;
                    let pattern = if request.text.is_empty() {
                        "*"
                    } else {
                        &request.text
                    };
                    let (next, keys): (u64, Vec<Vec<u8>>) = redis::cmd("SCAN")
                        .arg(cursor)
                        .arg("MATCH")
                        .arg(pattern)
                        .arg("COUNT")
                        .arg(100)
                        .query_async(&mut conn)
                        .await
                        .map_err(|_| "Redis SCAN 失败。")?;
                    let truncated = keys.len() > ROW_LIMIT;
                    Ok(Output {
                        columns: vec!["key".into()],
                        rows: keys
                            .into_iter()
                            .take(ROW_LIMIT)
                            .map(|k| vec![clipped(&k)])
                            .collect(),
                        truncated,
                        next_cursor: Some(next.to_string()),
                        note: format!("SCAN · 下一游标 {next} · COUNT 为提示值，可能有重复或空页"),
                        ..Default::default()
                    })
                }
                "preview" => {
                    let key = &request.target;
                    let kind: String = redis::cmd("TYPE")
                        .arg(key)
                        .query_async(&mut conn)
                        .await
                        .map_err(|_| "Redis TYPE 失败。")?;
                    let ttl: i64 = redis::cmd("TTL")
                        .arg(key)
                        .query_async(&mut conn)
                        .await
                        .map_err(|_| "Redis TTL 失败。")?;
                    let command = match kind.as_str() {
                        "string" => {
                            let mut c = redis::cmd("GETRANGE");
                            c.arg(key).arg(0).arg(65535);
                            c
                        }
                        "list" => {
                            let mut c = redis::cmd("LRANGE");
                            c.arg(key).arg(0).arg(99);
                            c
                        }
                        "hash" => {
                            let mut c = redis::cmd("HSCAN");
                            c.arg(key).arg(0).arg("COUNT").arg(100);
                            c
                        }
                        "set" => {
                            let mut c = redis::cmd("SSCAN");
                            c.arg(key).arg(0).arg("COUNT").arg(100);
                            c
                        }
                        "zset" => {
                            let mut c = redis::cmd("ZRANGE");
                            c.arg(key).arg(0).arg(99).arg("WITHSCORES");
                            c
                        }
                        "none" => return Err("该 key 已不存在。".into()),
                        _ => return Err(format!("暂未支持 {kind} 类型的预览。")),
                    };
                    let value: redis::Value = command
                        .query_async(&mut conn)
                        .await
                        .map_err(|_| "Redis 值读取失败。")?;
                    let mut budget = BYTE_LIMIT;
                    let value = redis_json(&value, &mut budget);
                    Ok(Output {
                        columns: vec!["key".into(), "type".into(), "TTL (s)".into(), "预览".into()],
                        rows: vec![vec![json!(key), json!(kind), json!(ttl), value]],
                        note: "有界预览，可能不是完整值 · TTL -1 为永不过期，-2 为不存在".into(),
                        ..Default::default()
                    })
                }
                _ => Err("不支持的 Redis 操作。".into()),
            }
        }
    }
}
fn redis_json(value: &redis::Value, budget: &mut usize) -> Value {
    if *budget == 0 {
        return json!("[展示已截断]");
    }
    match value {
        redis::Value::Nil => Value::Null,
        redis::Value::Int(n) => json!(n.to_string()),
        redis::Value::BulkString(b) => {
            *budget = budget.saturating_sub(b.len().min(CELL_LIMIT));
            clipped(&b)
        }
        redis::Value::Array(items) => Value::Array(
            items
                .iter()
                .take(500)
                .map(|v| redis_json(v, budget))
                .collect(),
        ),
        redis::Value::SimpleString(s) => json!(s),
        redis::Value::Okay => json!("OK"),
        _ => json!("[暂未支持此响应类型]"),
    }
}

async fn run(request: Request, state: &AppState) -> Result<Output, String> {
    if request.text.len() > 128 * 1024 || request.target.len() > 4096 {
        return Err("请求内容过长。".into());
    }
    let session = state
        .sessions
        .read()
        .await
        .get(&request.id)
        .cloned()
        .ok_or("连接已失效，请重新连接。")?;
    let started = Instant::now();
    let mut output = tokio::time::timeout(Duration::from_secs(20), execute(&session, &request))
        .await
        .map_err(|_| "客户端等待超时（20 秒），服务端执行状态尚未确认。".to_string())??;
    output.elapsed_ms = started.elapsed().as_millis();
    Ok(output)
}
/// Protocol-v1 service. All sessions and credentials remain inside this process.
#[derive(Default)]
pub struct Engine {
    state: AppState,
}
impl Engine {
    pub async fn dispatch(&self, method: &str, params: Value) -> Result<Value, String> {
        let result = match method {
            "hello" => {
                return Ok(
                    json!({"protocol":1,"version":env!("CARGO_PKG_VERSION"),"capabilities":["mysql","pg","es","redis"]}),
                )
            }
            "connect" => serde_json::to_value(
                connect(
                    serde_json::from_value(params).map_err(|_| "连接参数格式错误。")?,
                    &self.state,
                )
                .await?,
            ),
            "run" => serde_json::to_value(
                run(
                    serde_json::from_value(params).map_err(|_| "查询参数格式错误。")?,
                    &self.state,
                )
                .await?,
            ),
            "disconnect" => {
                let id = params
                    .get("id")
                    .and_then(Value::as_str)
                    .ok_or("缺少连接标识。")?;
                disconnect(id.into(), &self.state).await?;
                return Ok(Value::Null);
            }
            _ => return Err("不支持的协议方法。".into()),
        };
        result.map_err(|_| "响应序列化失败。".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_one_query() {
        for kind in ["mysql", "pg"] {
            assert!(validate_sql(kind, "SELECT 1;").is_ok());
            assert!(validate_sql(kind, "SELECT 'INTO' AS label").is_ok());
            assert!(validate_sql(kind, "SELECT 1 INTO new_table").is_err());
            assert!(validate_sql(kind, "WITH q AS (SELECT 1) SELECT * FROM q").is_ok());
            for sql in [
                "DELETE FROM t",
                "SELECT 1; COMMIT;",
                "BEGIN",
                "UPDATE t SET a=1",
                "",
                "SELECT 1; SELECT 2",
            ] {
                assert!(validate_sql(kind, sql).is_err(), "{sql}");
            }
        }
    }
    #[test]
    fn identifiers_and_payloads() {
        assert_eq!(quote_identifier("a`b", true), "`a``b`");
        assert_eq!(quote_identifier("a\"b", false), "\"a\"\"b\"");
        assert!(clipped(&vec![b'x'; CELL_LIMIT + 1])
            .as_str()
            .unwrap()
            .contains("展示已截断"));
        assert!(clipped(&[0xff]).as_str().unwrap().contains("二进制"));
    }
    fn fixture_config(kind: &str) -> Config {
        Config {
            kind: kind.into(),
            host: "127.0.0.1".into(),
            port: match kind {
                "mysql" => 13306,
                "pg" => 16432,
                "redis" => 16379,
                _ => 19200,
            },
            username: match kind {
                "mysql" => "root",
                "pg" => "datax_fixture",
                _ => "",
            }
            .into(),
            password: "".into(),
            database: match kind {
                "mysql" => "datax_fixture",
                "pg" => "postgres",
                "redis" => "0",
                _ => "",
            }
            .into(),
            tls: false,
            endpoint: "http://127.0.0.1:19200".into(),
            api_key: "".into(),
        }
    }
    async fn fixture_run(
        session: &Session,
        action: &str,
        text: &str,
        target: &str,
    ) -> Result<Output, String> {
        execute(
            session,
            &Request {
                id: "fixture".into(),
                action: action.into(),
                text: text.into(),
                target: target.into(),
                cursor: "0".into(),
            },
        )
        .await
    }
    #[tokio::test]
    #[ignore = "requires scripts/fixtures.py start; isolated local servers only"]
    async fn local_adapters() {
        for kind in ["mysql", "pg"] {
            let session = open_session(fixture_config(kind)).await.unwrap();
            let out = fixture_run(
                &session,
                "query",
                "SELECT id, label, NULL AS missing FROM sample",
                "",
            )
            .await
            .unwrap();
            assert_eq!(out.rows[0][0], json!("9007199254740993"));
            assert_eq!(out.rows[0][1], json!("本地测试"));
            assert_eq!(out.rows[0][2], Value::Null);
            let catalog = fixture_run(&session, "catalog", "", "").await.unwrap();
            assert!(catalog.rows.iter().any(|r| r[1] == "sample"));
            let schema = if kind == "mysql" {
                "datax_fixture"
            } else {
                "public"
            };
            let preview = fixture_run(
                &session,
                "preview",
                "",
                &json!([schema, "sample"]).to_string(),
            )
            .await
            .unwrap();
            assert!(!preview.rows.is_empty());
            let many = if kind == "mysql" {
                "WITH RECURSIVE n AS (SELECT 1 AS v UNION ALL SELECT v+1 FROM n WHERE v<600) SELECT * FROM n"
            } else {
                "SELECT generate_series(1,600)"
            };
            let limited = fixture_run(&session, "query", many, "").await.unwrap();
            assert_eq!(limited.rows.len(), ROW_LIMIT);
            assert!(limited.truncated);
            let large = if kind == "mysql" {
                "SELECT REPEAT('x',70000)"
            } else {
                "SELECT repeat('x',70000)"
            };
            let clipped = fixture_run(&session, "query", large, "").await.unwrap();
            assert!(clipped.truncated);
            assert!(fixture_run(&session, "query", "DELETE FROM sample", "")
                .await
                .is_err());
            if kind == "pg" {
                assert!(fixture_run(&session,"query","WITH x AS (INSERT INTO sample VALUES (2,'blocked') RETURNING *) SELECT * FROM x", "").await.is_err());
            }
            // Reusing the pool after truncation or an error must still work.
            assert_eq!(
                fixture_run(&session, "query", "SELECT COUNT(*) FROM sample", "")
                    .await
                    .unwrap()
                    .rows[0][0],
                json!("1")
            );
            match session {
                Session::Mysql(p) => p.close().await,
                Session::Pg(p) => p.close().await,
                _ => {}
            }
        }
        let redis = open_session(fixture_config("redis")).await.unwrap();
        let keys = fixture_run(&redis, "query", "datax:*", "").await.unwrap();
        assert!(keys.rows.iter().any(|r| r[0] == "datax:fixture"));
        let value = fixture_run(&redis, "preview", "", "datax:fixture")
            .await
            .unwrap();
        assert_eq!(value.rows[0][3], json!("本地测试"));
        assert_eq!(
            fixture_run(&redis, "preview", "", "datax:hash")
                .await
                .unwrap()
                .rows[0][1],
            json!("hash")
        );
        let es = open_session(fixture_config("es")).await.unwrap();
        assert_eq!(
            fixture_run(&es, "catalog", "", "").await.unwrap().rows[0][0],
            json!("datax-fixture")
        );
        let docs = fixture_run(
            &es,
            "query",
            r#"{"size":9999,"query":{"match_all":{}}}"#,
            "datax-fixture",
        )
        .await
        .unwrap();
        assert_eq!(docs.rows[0][1], json!("1"));
        assert!(fixture_run(&es, "query", "{}", "../_security")
            .await
            .is_err());
    }
}
