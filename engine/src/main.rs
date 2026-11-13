use cs_tool_engine::Engine;
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    io::{self, BufRead, Read, Write},
    sync::Arc,
};
use tokio::sync::{mpsc, Semaphore};
const MAX_REQUEST: u64 = 256 * 1024;
const MAX_RESPONSE: usize = 16 * 1024 * 1024;
#[derive(Deserialize)]
struct Request {
    id: u64,
    method: String,
    #[serde(default)]
    params: Value,
}

#[tokio::main]
async fn main() {
    let (requests_tx, mut requests_rx) = mpsc::channel::<Vec<u8>>(4);
    std::thread::spawn(move || {
        let stdin = io::stdin();
        let mut input = stdin.lock();
        loop {
            let mut bytes = Vec::new();
            match input
                .by_ref()
                .take(MAX_REQUEST + 1)
                .read_until(b'\n', &mut bytes)
            {
                Ok(0) | Err(_) => break,
                Ok(_) if bytes.len() as u64 > MAX_REQUEST || !bytes.ends_with(b"\n") => break,
                Ok(_) => {
                    if requests_tx.blocking_send(bytes).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let (replies_tx, mut replies_rx) = mpsc::channel::<Vec<u8>>(2);
    let writer = std::thread::spawn(move || {
        let stdout = io::stdout();
        let mut output = stdout.lock();
        while let Some(bytes) = replies_rx.blocking_recv() {
            if output
                .write_all(&bytes)
                .and_then(|_| output.write_all(b"\n"))
                .and_then(|_| output.flush())
                .is_err()
            {
                break;
            }
        }
    });
    let engine = Arc::new(Engine::default());
    let limit = Arc::new(Semaphore::new(4));
    let mut tasks = tokio::task::JoinSet::new();
    while let Some(bytes) = requests_rx.recv().await {
        let Ok(request) = serde_json::from_slice::<Request>(&bytes) else {
            break;
        };
        let Ok(permit) = limit.clone().acquire_owned().await else {
            break;
        };
        let engine = engine.clone();
        let replies = replies_tx.clone();
        tasks.spawn(async move {
            let response = match engine.dispatch(&request.method, request.params).await {
                Ok(result) => json!({"id":request.id,"ok":true,"result":result}),
                Err(error) => json!({"id":request.id,"ok":false,"error":error}),
            };
            if let Ok(mut bytes) = serde_json::to_vec(&response) {
                if bytes.len() > MAX_RESPONSE {
                    bytes = serde_json::to_vec(&json!({"id":request.id,"ok":false,"error":"响应超过客户端上限，请缩小查询范围。"})).unwrap_or_default();
                }
                let _ = replies.send(bytes).await;
            }
            drop(permit);
        });
        while tasks.try_join_next().is_some() {}
    }
    // Parent exit closes stdin. Drop in-flight futures and sockets rather than
    // leaving a detached worker or waiting indefinitely on the remote server.
    tasks.abort_all();
    while tasks.join_next().await.is_some() {}
    drop(replies_tx);
    let _ = writer.join();
}
