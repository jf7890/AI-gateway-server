import os
import sqlite3
import logging
from typing import Dict, Any, List, Optional
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import HTMLResponse, JSONResponse
import litellm

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ai-gateway")

app = FastAPI(title="Red Lab AI Gateway", version="1.0.0")

DB_PATH = os.environ.get("GATEWAY_DB", "data/gateway.sqlite")

def get_db():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = get_db()
    with conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS prompts (
                id INTEGER PRIMARY KEY,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                active BOOLEAN DEFAULT 1
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS logs (
                id INTEGER PRIMARY KEY,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                ip_address TEXT,
                model TEXT,
                provider TEXT,
                request_tokens INTEGER,
                response_tokens INTEGER,
                duration_ms INTEGER,
                status_code INTEGER,
                error_message TEXT
            )
        """)
        # Insert default red-team web coach prompt if completely empty
        cursor = conn.execute("SELECT count(*) as cnt FROM prompts")
        if cursor.fetchone()['cnt'] == 0:
            default_prompt = (
                "You are an expert Ethical Hacking Coach, specialized strictly in Web Application Security. "
                "The user is a student in a red-team lab. "
                "You are provided with the terminal context (what they just ran) and their question. "
                "CRITICAL INSTRUCTIONS: "
                "1. NEVER give the exact command to run. "
                "2. Analyze their error or output and explain WHY it failed or what it means. "
                "3. Guide them towards the next logical step conceptually (e.g., 'Have you considered trying to bypass the filter using URL encoding?' instead of 'Run sqlmap --tamper=space2comment'). "
                "4. Restrict all context and guidance to Web vulnerabilities (SQLi, XSS, SSRF, LFI, etc.). If they ask about system exploits (like kernel rootkits), decline politely."
            )
            conn.execute("INSERT INTO prompts (role, content, active) VALUES ('system', ?, 1)", (default_prompt,))
    conn.close()

@app.on_event("startup")
def startup_event():
    init_db()

def get_active_system_prompt() -> str:
    conn = get_db()
    cursor = conn.execute("SELECT content FROM prompts WHERE role='system' AND active=1 ORDER BY id DESC LIMIT 1")
    row = cursor.fetchone()
    conn.close()
    if row:
        return row['content']
    return "You are a helpful Red Team Assistant."

def log_request(ip: str, model: str, req_tokens: int, res_tokens: int, duration: float, error: str = ""):
    conn = get_db()
    with conn:
        conn.execute(
            "INSERT INTO logs (ip_address, model, request_tokens, response_tokens, duration_ms, error_message) VALUES (?, ?, ?, ?, ?, ?)",
            (ip, model, req_tokens, res_tokens, int(duration * 1000) if duration else 0, error)
        )
    conn.close()

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """
    OpenAI API Compatible Endpoint for chat completions.
    """
    body = await request.json()
    model = body.get("model", "openai/gpt-3.5-turbo") # Example default
    messages = body.get("messages", [])
    
    # Extract API key
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid API Key")
    api_key = auth_header.split(" ")[1]

    # Prepend System Prompt
    system_prompt = get_active_system_prompt()
    
    # Check if system message already exists and replace it, or prepend it
    new_messages = [{"role": "system", "content": system_prompt}]
    for msg in messages:
        if msg.get("role") != "system":
            new_messages.append(msg)
    
    body["messages"] = new_messages

    # Map model to provider requirement if needed (handled by litellm typically)
    try:
        # LiteLLM will route based on standard prefixes like 'groq/llama-3-8b', 'openrouter/...', etc.
        # We temporarily set API key environment variably if litellm expects it, 
        # but litellm `completion()` accepts `api_key` param!
        
        response = litellm.completion(
            model=model,
            messages=new_messages,
            api_key=api_key,
            stream=body.get("stream", False),
            temperature=body.get("temperature", 0.7)
        )
        
        # Log successful request
        client_ip = request.client.host if request.client else "unknown"
        logger.info(f"Processed request for {model} from {client_ip}")
        # Note: If streaming is true, we cannot log tokens easily without a callback. 
        # Assuming non-streaming for the MVP Logging:
        if not body.get("stream"):
            log_request(
                client_ip, 
                model, 
                response.usage.prompt_tokens if hasattr(response, 'usage') else 0,
                response.usage.completion_tokens if hasattr(response, 'usage') else 0,
                0.0
            )

        return response.model_dump()
        
    except Exception as e:
        logger.error(f"Error calling LLM: {str(e)}")
        log_request(request.client.host if request.client else "unknown", model, 0, 0, 0.0, str(e))
        raise HTTPException(status_code=500, detail=f"LLM Provider Error: {str(e)}")

@app.get("/dashboard", response_class=HTMLResponse)
async def get_dashboard():
    """
    Instructor Dashboard UI (Extremely Simple MVP)
    """
    conn = get_db()
    logs_cursor = conn.execute("SELECT * FROM logs ORDER BY id DESC LIMIT 50")
    logs = logs_cursor.fetchall()
    conn.close()
    
    html = """
    <html>
        <head><title>AI Gateway Dashboard</title></head>
        <body style="font-family: sans-serif; padding: 20px;">
            <h2>Red Lab AI Gateway - Instructor Logs</h2>
            <table border="1" cellpadding="5" style="border-collapse: collapse; width: 100%;">
                <tr>
                    <th>ID</th><th>Time</th><th>IP Address</th><th>Model</th>
                    <th>Req Tokens</th><th>Res Tokens</th><th>Error</th>
                </tr>
    """
    for row in logs:
        html += f"<tr><td>{row['id']}</td><td>{row['timestamp']}</td><td>{row['ip_address']}</td>"
        html += f"<td>{row['model']}</td><td>{row['request_tokens']}</td><td>{row['response_tokens']}</td>"
        html += f"<td>{row['error_message']}</td></tr>"
    html += """
            </table>
        </body>
    </html>
    """
    return html

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
