import os
import uuid
import secrets
import sqlite3
import json
from datetime import datetime
from flask import Flask, request, jsonify, g, send_from_directory

app = Flask(__name__, static_folder='static', template_folder='templates')
DB_PATH = os.path.join(os.path.dirname(__file__), 'santa.db')

# ── Database ──────────────────────────────────────────────────────────────────

def get_db():
    if 'db' not in g:
        g.db = sqlite3.connect(DB_PATH, detect_types=sqlite3.PARSE_DECLTYPES)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA journal_mode=WAL")
    return g.db

@app.teardown_appcontext
def close_db(e=None):
    db = g.pop('db', None)
    if db:
        db.close()

def init_db():
    with sqlite3.connect(DB_PATH) as db:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS events (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            budget      REAL NOT NULL DEFAULT 0,
            event_date  TEXT,
            is_assigned INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS participants (
            id              TEXT PRIMARY KEY,
            event_id        TEXT NOT NULL,
            name            TEXT NOT NULL,
            email           TEXT,
            token           TEXT NOT NULL UNIQUE,
            assigned_to_id  TEXT,
            wishlist        TEXT,
            FOREIGN KEY (event_id) REFERENCES events(id)
        );
        """)

init_db()

# ── Helpers ───────────────────────────────────────────────────────────────────

def row_to_dict(row):
    return dict(row) if row else None

def derangement_shuffle(ids):
    """Fisher-Yates derangement: no element maps to itself."""
    if len(ids) < 2:
        return None
    lst = list(ids)
    for attempt in range(1000):
        shuffled = list(lst)
        for i in range(len(shuffled) - 1, 0, -1):
            j = secrets.randbelow(i + 1)
            shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        if all(shuffled[i] != lst[i] for i in range(len(lst))):
            return shuffled
    return None  # extremely unlikely

# ── Routes: Serve Frontend ────────────────────────────────────────────────────

@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

@app.route('/event/<event_id>')
def event_page(event_id):
    return send_from_directory('static', 'index.html')

@app.route('/reveal/<token>')
def reveal_page(token):
    return send_from_directory('static', 'index.html')

# ── API: Events ───────────────────────────────────────────────────────────────

@app.route('/api/events', methods=['POST'])
def create_event():
    data = request.get_json(force=True)
    name = (data.get('name') or '').strip()
    if not name:
        return jsonify(error='Event name is required'), 400
    budget = float(data.get('budget') or 0)
    event_date = data.get('event_date') or None
    event_id = str(uuid.uuid4())[:8].upper()
    now = datetime.utcnow().isoformat()
    db = get_db()
    db.execute(
        "INSERT INTO events (id, name, budget, event_date, is_assigned, created_at) VALUES (?,?,?,?,0,?)",
        (event_id, name, budget, event_date, now)
    )
    db.commit()
    return jsonify(id=event_id, name=name, budget=budget, event_date=event_date, is_assigned=False), 201

@app.route('/api/events/<event_id>', methods=['GET'])
def get_event(event_id):
    db = get_db()
    event = row_to_dict(db.execute("SELECT * FROM events WHERE id=?", (event_id,)).fetchone())
    if not event:
        return jsonify(error='Event not found'), 404
    participants = [row_to_dict(r) for r in db.execute(
        "SELECT id, name, email, token, wishlist FROM participants WHERE event_id=? ORDER BY rowid",
        (event_id,)
    ).fetchall()]
    event['participants'] = participants
    event['is_assigned'] = bool(event['is_assigned'])
    return jsonify(event)

# ── API: Participants ─────────────────────────────────────────────────────────

@app.route('/api/events/<event_id>/participants', methods=['POST'])
def add_participant(event_id):
    db = get_db()
    event = db.execute("SELECT * FROM events WHERE id=?", (event_id,)).fetchone()
    if not event:
        return jsonify(error='Event not found'), 404
    if event['is_assigned']:
        return jsonify(error='Assignments already made; cannot add participants'), 400
    data = request.get_json(force=True)
    name = (data.get('name') or '').strip()
    if not name:
        return jsonify(error='Name is required'), 400
    email = (data.get('email') or '').strip() or None
    pid = str(uuid.uuid4())
    token = secrets.token_urlsafe(16)
    db.execute(
        "INSERT INTO participants (id, event_id, name, email, token) VALUES (?,?,?,?,?)",
        (pid, event_id, name, email, token)
    )
    db.commit()
    return jsonify(id=pid, name=name, email=email, token=token), 201

@app.route('/api/events/<event_id>/participants/<pid>', methods=['DELETE'])
def remove_participant(event_id, pid):
    db = get_db()
    event = db.execute("SELECT * FROM events WHERE id=?", (event_id,)).fetchone()
    if not event:
        return jsonify(error='Event not found'), 404
    if event['is_assigned']:
        return jsonify(error='Cannot remove after assignments made'), 400
    db.execute("DELETE FROM participants WHERE id=? AND event_id=?", (pid, event_id))
    db.commit()
    return jsonify(ok=True)

# ── API: Assign ───────────────────────────────────────────────────────────────

@app.route('/api/events/<event_id>/assign', methods=['POST'])
def assign(event_id):
    db = get_db()
    event = db.execute("SELECT * FROM events WHERE id=?", (event_id,)).fetchone()
    if not event:
        return jsonify(error='Event not found'), 404
    if event['is_assigned']:
        return jsonify(error='Already assigned'), 400
    rows = db.execute("SELECT id FROM participants WHERE event_id=?", (event_id,)).fetchall()
    ids = [r['id'] for r in rows]
    if len(ids) < 3:
        return jsonify(error='Need at least 3 participants to assign'), 400
    shuffled = derangement_shuffle(ids)
    if shuffled is None:
        return jsonify(error='Could not generate valid assignment, try again'), 500
    for giver_id, receiver_id in zip(ids, shuffled):
        db.execute("UPDATE participants SET assigned_to_id=? WHERE id=?", (receiver_id, giver_id))
    db.execute("UPDATE events SET is_assigned=1 WHERE id=?", (event_id,))
    db.commit()
    return jsonify(ok=True, message='Assignments made! Share tokens with participants.')

# ── API: Reveal ───────────────────────────────────────────────────────────────

@app.route('/api/reveal/<token>', methods=['GET'])
def reveal(token):
    db = get_db()
    giver = row_to_dict(db.execute("SELECT * FROM participants WHERE token=?", (token,)).fetchone())
    if not giver:
        return jsonify(error='Invalid token'), 404
    event = row_to_dict(db.execute("SELECT * FROM events WHERE id=?", (giver['event_id'],)).fetchone())
    if not event['is_assigned']:
        return jsonify(error='Assignments not yet made'), 400
    receiver = row_to_dict(db.execute(
        "SELECT name, wishlist FROM participants WHERE id=?", (giver['assigned_to_id'],)
    ).fetchone())
    return jsonify(
        giver_name=giver['name'],
        receiver_name=receiver['name'],
        receiver_wishlist=receiver['wishlist'],
        budget=event['budget'],
        event_name=event['name'],
        event_date=event['event_date']
    )

# ── API: Wishlist ─────────────────────────────────────────────────────────────

@app.route('/api/reveal/<token>/wishlist', methods=['POST'])
def update_wishlist(token):
    db = get_db()
    p = db.execute("SELECT id FROM participants WHERE token=?", (token,)).fetchone()
    if not p:
        return jsonify(error='Invalid token'), 404
    data = request.get_json(force=True)
    wishlist = (data.get('wishlist') or '').strip()
    db.execute("UPDATE participants SET wishlist=? WHERE id=?", (wishlist, p['id']))
    db.commit()
    return jsonify(ok=True)

if __name__ == '__main__':
    app.run(debug=True, port=5000)
