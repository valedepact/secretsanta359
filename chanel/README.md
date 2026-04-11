# 🎅 Secret Santa App

A full-stack Secret Santa organiser — Python (Flask) backend, Vanilla JS frontend.

## Requirements
- Python 3.8+
- Flask (`pip install flask`)

## Run
```bash
bash run.sh
# or
python3 app.py
```
Then open **http://localhost:5000** in your browser.

## How It Works

### Admin (Event Organiser)
1. Go to the home page → **Create an Event** (name, budget, date)
2. You'll land on the **Event Dashboard** — share the Event ID with participants
3. Add participants (name + optional email)
4. When everyone is added (min 3), click **Assign Secret Santas!**
5. Each participant row now shows a **token chip** — copy & send each token to the right person

### Participant
1. Visit the app and paste your **token** in the Join box (or use the link with `#reveal/<token>`)
2. Click the gift box reveal to see **who you're buying for**
3. Optionally save your own wishlist so your Secret Santa knows what to get you

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/events` | Create event |
| GET | `/api/events/:id` | Get event + participants |
| POST | `/api/events/:id/participants` | Add participant |
| DELETE | `/api/events/:id/participants/:pid` | Remove participant |
| POST | `/api/events/:id/assign` | Run assignment algorithm |
| GET | `/api/reveal/:token` | Get assignment for token |
| POST | `/api/reveal/:token/wishlist` | Save wishlist |

## Security Notes
- Assignments are locked after being made — no admin can see who got who
- Participants access their assignment only via a cryptographically random token (`secrets.token_urlsafe`)
- Derangement shuffle ensures no one is assigned themselves
