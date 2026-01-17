import json
import os
import time
import uuid
import boto3
from decimal import Decimal

DDB_TABLE = os.environ["DDB_TABLE"]
ddb = boto3.resource("dynamodb")
table = ddb.Table(DDB_TABLE)

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            # DynamoDB returns numbers as Decimal
            if obj % 1 == 0:
                return int(obj)
            return float(obj)
        return super().default(obj)

def _response(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
        },
        "body": json.dumps(body, cls=DecimalEncoder),
    }

def handler(event, context):
    method = (event.get("requestContext", {}) or {}).get("http", {}).get("method") or event.get("httpMethod", "")
    path = event.get("rawPath") or event.get("path") or "/"

    if method == "OPTIONS":
        return _response(200, {"ok": True})

    now = int(time.time())

    if path == "/notes" and method == "GET":
        resp = table.scan(Limit=25)
        items = resp.get("Items", [])
        items.sort(key=lambda x: x.get("createdAt", 0), reverse=True)
        return _response(200, {"items": items})

    if path == "/notes" and method == "POST":
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            import base64
            body = base64.b64decode(body).decode("utf-8")

        data = json.loads(body)
        text = (data.get("text") or "").strip()
        if not text:
            return _response(400, {"error": "text is required"})

        note_id = "n_" + uuid.uuid4().hex[:16]
        item = {
            "noteId": note_id,
            "createdAt": now,
            "text": text,
        }
        table.put_item(Item=item)
        return _response(201, item)

    if path.startswith("/notes/") and method == "DELETE":
        note_id = path.split("/notes/")[1]
        if not note_id:
            return _response(400, {"error": "noteId required"})
        table.delete_item(Key={"noteId": note_id})
        return _response(200, {"deleted": note_id})

    return _response(404, {"error": "Not Found", "method": method, "path": path})
