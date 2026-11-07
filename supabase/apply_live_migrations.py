import os
import sys
import json
import urllib.request
import urllib.error

PROJECT_REF = os.environ.get("SUPABASE_PROJECT_REF", "awzxwsmfyrbnnuqkxuxu")
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
if not TOKEN:
    # Check fallback or raise
    TOKEN = "sbp_oauth_18a5ea4409a1eb2dec7026b38cc77383c3e6c183" # Local migration runner default
URL = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query"

def execute_query(query: str):
    data = json.dumps({"query": query}).encode("utf-8")
    req = urllib.request.Request(URL, data=data, headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json"
    })
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        raise RuntimeError(f"HTTP {e.code}: {err_body}")

def split_statements(sql: str):
    """Split SQL file into discrete executable statements handling comments, quotes, and dollar-quotes."""
    statements = []
    current = []
    in_single_quote = False
    in_double_quote = False
    dollar_tag = None
    i = 0
    length = len(sql)

    while i < length:
        ch = sql[i]
        
        # Check comments
        if not in_single_quote and not in_double_quote and dollar_tag is None:
            if ch == '-' and i + 1 < length and sql[i+1] == '-':
                # Line comment
                eol = sql.find('\n', i)
                if eol == -1:
                    break
                i = eol + 1
                continue
            if ch == '/' and i + 1 < length and sql[i+1] == '*':
                # Block comment
                end_bc = sql.find('*/', i + 2)
                if end_bc == -1:
                    break
                i = end_bc + 2
                continue

        # Check dollar quoting $$ or $tag$
        if not in_single_quote and not in_double_quote:
            if ch == '$':
                # find matching end of tag
                next_dollar = sql.find('$', i + 1)
                if next_dollar != -1 and next_dollar - i <= 30:
                    potential_tag = sql[i:next_dollar+1]
                    if dollar_tag is None and (potential_tag == '$$' or potential_tag.strip('$').isalnum() or potential_tag.strip('$') == ''):
                        dollar_tag = potential_tag
                        current.append(potential_tag)
                        i = next_dollar + 1
                        continue
                    elif dollar_tag is not None and potential_tag == dollar_tag:
                        dollar_tag = None
                        current.append(potential_tag)
                        i = next_dollar + 1
                        continue

        if dollar_tag is None:
            if ch == "'" and not in_double_quote:
                # check for escaped single quote ''
                if in_single_quote and i + 1 < length and sql[i+1] == "'":
                    current.append("''")
                    i += 2
                    continue
                in_single_quote = not in_single_quote
            elif ch == '"' and not in_single_quote:
                in_double_quote = not in_double_quote
            elif ch == ';' and not in_single_quote and not in_double_quote:
                stmt = "".join(current).strip()
                if stmt:
                    statements.append(stmt)
                current = []
                i += 1
                continue

        current.append(ch)
        i += 1

    last_stmt = "".join(current).strip()
    if last_stmt:
        statements.append(last_stmt)

    return statements

def apply_migration(file_path: str):
    filename = os.path.basename(file_path)
    print(f"\n=======================================================")
    print(f"Applying migration: {filename}")
    print(f"=======================================================")
    
    with open(file_path, "r", encoding="utf-8") as f:
        sql = f.read()

    stmts = split_statements(sql)
    print(f"Parsed {len(stmts)} statements.")
    
    for idx, stmt in enumerate(stmts, 1):
        preview = stmt.replace("\n", " ")[:70]
        try:
            execute_query(stmt)
            print(f"  [{idx:03d}/{len(stmts):03d}] ✓ {preview}...")
        except Exception as e:
            print(f"\n❌ Error on statement {idx}:\n{stmt}\nError: {e}")
            sys.exit(1)

    print(f"✅ Successfully applied {filename} ({len(stmts)} statements).")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        files = sys.argv[1:]
    else:
        files = [
            "supabase/migrations/0010_emergency_security_hardening.sql",
            "supabase/migrations/0011_target_architecture_core.sql",
            "supabase/migrations/0012_target_rpcs_and_sync.sql",
        ]
    for mig in files:
        apply_migration(mig)
    print("\n🎉 ALL MIGRATIONS APPLIED TO LIVE SUPABASE PROJECT SUCCESSFULLY!")

