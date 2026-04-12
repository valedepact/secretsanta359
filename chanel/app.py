import os
import uuid
import secrets
from datetime import datetime, timezone
from flask import Flask, request, jsonify, send_from_directory
from supabase import create_client, Client

app = Flask(__name__, static_folder='static', template_folder='templates')

SUPABASE_URL = os.environ.get('SUPABASE_URL', 'https://mebvnpoynqbuoqlzzvvw.supabase.co')
SUPABASE_KEY = os.environ.get('SUPABASE_KEY', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1lYnZucG95bnFidW9xbHp6dnZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4NTU2MTYsImV4cCI6MjA5MTQzMTYxNn0.igqg0gkS1kLIpc-9q8FatGmCGyQBDrePrwlPbQjRNP0')

sb: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ── Helpers ───────────────────────────────────────────────────────────────────

def gender_aware_assign(participants):
    ids     = [p['id'] for p in participants]
    genders = {p['id']: p['gender'] for p in participants}

    for _ in range(2000):
        assignment = {}

        def preferred_receivers(giver_id, remaining):
            g = genders[giver_id]
            if g == 'male':
                cross = [r for r in remaining if genders[r] == 'female' and r != giver_id]
                same  = [r for r in remaining if genders[r] != 'female' and r != giver_id]
            elif g == 'female':
                cross = [r for r in remaining if genders[r] == 'male' and r != giver_id]
                same  = [r for r in remaining if genders[r] != 'male' and r != giver_id]
            else:
                cross = [r for r in remaining if r != giver_id]
                same  = []
            secrets.SystemRandom().shuffle(cross)
            secrets.SystemRandom().shuffle(same)
            return cross + same

        givers = list(ids)
        secrets.SystemRandom().shuffle(givers)
        remaining = list(ids)
        secrets.SystemRandom().shuffle(remaining)
        success = True

        for giver in givers:
            options = preferred_receivers(giver, remaining)
            if not options:
                success = False
                break
            chosen = options[0]
            assignment[giver] = chosen
            remaining.remove(chosen)

        if success and len(assignment) == len(ids):
            return assignment

    return None

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
    admin_pin = (data.get('admin_pin') or '').strip()
    if not admin_pin:
        return jsonify(error='A PIN is required'), 400
    budget = float(data.get('budget') or 0)
    event_date = data.get('event_date') or None
    event_id = str(uuid.uuid4())[:8].upper()
    now = datetime.now(timezone.utc).isoformat()

    sb.table('events').insert({
        'id': event_id, 'name': name, 'budget': budget,
        'event_date': event_date, 'admin_pin': admin_pin,
        'is_assigned': 0, 'created_at': now
    }).execute()

    return jsonify(id=event_id, name=name, budget=budget,
                   event_date=event_date, is_assigned=False), 201

@app.route('/api/events/<event_id>', methods=['GET'])
def get_event(event_id):
    res = sb.table('events').select('*').eq('id', event_id).execute()
    if not res.data:
        return jsonify(error='Event not found'), 404
    event = res.data[0]

    pres = sb.table('participants').select(
        'id, name, email, gender, token, wishlist'
    ).eq('event_id', event_id).execute()

    event['participants'] = pres.data
    event['is_assigned'] = bool(event['is_assigned'])
    return jsonify(event)

@app.route('/api/events/<event_id>/verify', methods=['POST'])
def verify_pin(event_id):
    res = sb.table('events').select('admin_pin').eq('id', event_id).execute()
    if not res.data:
        return jsonify(error='Event not found'), 404
    data = request.get_json(force=True)
    pin = (data.get('admin_pin') or '').strip()
    if pin != res.data[0]['admin_pin']:
        return jsonify(error='Incorrect PIN'), 403
    return jsonify(ok=True)

# ── API: Participants ─────────────────────────────────────────────────────────

@app.route('/api/events/<event_id>/participants', methods=['POST'])
def add_participant(event_id):
    res = sb.table('events').select('is_assigned').eq('id', event_id).execute()
    if not res.data:
        return jsonify(error='Event not found'), 404
    if res.data[0]['is_assigned']:
        return jsonify(error='Assignments already made; cannot add participants'), 400

    data = request.get_json(force=True)
    name = (data.get('name') or '').strip()
    if not name:
        return jsonify(error='Name is required'), 400
    email  = (data.get('email') or '').strip() or None
    gender = (data.get('gender') or 'unspecified').strip().lower()
    if gender not in ('male', 'female', 'unspecified'):
        gender = 'unspecified'
    pid   = str(uuid.uuid4())
    token = secrets.token_urlsafe(16)

    sb.table('participants').insert({
        'id': pid, 'event_id': event_id, 'name': name,
        'email': email, 'gender': gender, 'token': token
    }).execute()

    return jsonify(id=pid, name=name, email=email, gender=gender, token=token), 201

@app.route('/api/events/<event_id>/participants/<pid>', methods=['DELETE'])
def remove_participant(event_id, pid):
    res = sb.table('events').select('is_assigned').eq('id', event_id).execute()
    if not res.data:
        return jsonify(error='Event not found'), 404
    if res.data[0]['is_assigned']:
        return jsonify(error='Cannot remove after assignments made'), 400
    sb.table('participants').delete().eq('id', pid).eq('event_id', event_id).execute()
    return jsonify(ok=True)

# ── API: Assign ───────────────────────────────────────────────────────────────

@app.route('/api/events/<event_id>/assign', methods=['POST'])
def assign(event_id):
    res = sb.table('events').select('is_assigned').eq('id', event_id).execute()
    if not res.data:
        return jsonify(error='Event not found'), 404
    if res.data[0]['is_assigned']:
        return jsonify(error='Already assigned'), 400

    pres = sb.table('participants').select('id, gender').eq('event_id', event_id).execute()
    participants = pres.data
    if len(participants) < 3:
        return jsonify(error='Need at least 3 participants to assign'), 400

    assignment = gender_aware_assign(participants)
    if assignment is None:
        return jsonify(error='Could not generate valid assignment, try again'), 500

    for giver_id, receiver_id in assignment.items():
        sb.table('participants').update(
            {'assigned_to_id': receiver_id}
        ).eq('id', giver_id).execute()

    sb.table('events').update({'is_assigned': 1}).eq('id', event_id).execute()
    return jsonify(ok=True, message='Assignments made! Share tokens with participants.')

# ── API: Reveal ───────────────────────────────────────────────────────────────

@app.route('/api/reveal/<token>', methods=['GET'])
def reveal(token):
    res = sb.table('participants').select('*').eq('token', token).execute()
    if not res.data:
        return jsonify(error='Invalid token'), 404
    giver = res.data[0]

    eres = sb.table('events').select('*').eq('id', giver['event_id']).execute()
    event = eres.data[0]
    if not event['is_assigned']:
        return jsonify(error='Assignments not yet made'), 400

    rres = sb.table('participants').select(
        'name, wishlist'
    ).eq('id', giver['assigned_to_id']).execute()
    receiver = rres.data[0]

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
    res = sb.table('participants').select('id').eq('token', token).execute()
    if not res.data:
        return jsonify(error='Invalid token'), 404
    data = request.get_json(force=True)
    wishlist = (data.get('wishlist') or '').strip()
    sb.table('participants').update(
        {'wishlist': wishlist}
    ).eq('id', res.data[0]['id']).execute()
    return jsonify(ok=True)

if __name__ == '__main__':
    app.run(debug=True, port=5000)