#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# NEXUTUBE COMPLETE v2.1.0
# Plateforme video + integration ytscrape (YouTube sans cle API).
# Auteur : Aissa Mohammedi (DGK)
# Licence : NEXUS-OPEN-2.0
# Compatible a-Shell iOS - os.path uniquement - stdlib pure
# ytscrape : optionnel, fallback si absent.

import os
import re
import sys
import json
import math
import time
import hmac
import uuid
import sqlite3
import hashlib
import threading
import urllib.parse
import urllib.request
import urllib.error
import mimetypes
import ssl
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "2.1.0"
AUTEUR = "Aissa Mohammedi (DGK)"
LICENCE = "NEXUS-OPEN-2.0"

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, "Documents", "nexutube")
os.makedirs(BASE, exist_ok=True)
VIDEOS_DIR = os.path.join(BASE, "videos")
os.makedirs(VIDEOS_DIR, exist_ok=True)
THUMBS_DIR = os.path.join(BASE, "thumbnails")
os.makedirs(THUMBS_DIR, exist_ok=True)
DB_PATH = os.path.join(BASE, "nexutube.db")
LOG_FILE = os.path.join(BASE, "nexutube.log")

PORT = 8079
SECRET = b"nexutube-secret-key-2026"

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

# ===============================================================
# DETECTION ytscrape
# ===============================================================

YTSCRAPE_OK = False
try:
from ytscrape import YouTube, SearchFilter
YTSCRAPE_OK = True
except ImportError:
YTSCRAPE_OK = False

LOG_LOCK = threading.RLock()


def log(msg):
ts = datetime.now(timezone.utc).isoformat()
line = "[" + ts + "] " + str(msg)
with LOG_LOCK:
try:
print(line, flush=True)
except Exception:
pass
try:
with open(LOG_FILE, "a", encoding="utf-8") as f:
f.write(line + "\n")
except OSError:
pass


# ===============================================================
# YOUTUBE VIA ytscrape (SANS CLE API)
# ===============================================================

def yt_search_scrape(query, max_results=25):
"""Recherche YouTube via ytscrape (aucune cle API)."""
if not YTSCRAPE_OK:
return {"erreur": "ytscrape non installe", "code": 0}

try:
with YouTube(language="fr", region="CA") as yt:
resultats = []
for v in yt.search(query, filter=SearchFilter.VIDEOS, max_results=max_results):
resultats.append({
"video_id": getattr(v, "id", "") or "",
"titre": getattr(v, "title", "") or "",
"chaine_nom": getattr(v, "channel", {}).get("name", "") if hasattr(v, "channel") and isinstance(getattr(v, "channel"), dict) else getattr(v, "channel", "") or "",
"thumbnail": getattr(v, "thumbnail", "") or "",
"duree": int(getattr(v, "length_seconds", 0) or 0),
"vues": int(getattr(v, "views", 0) or 0),
"url": getattr(v, "url", "") or "",
"embed": "https://www.youtube.com/embed/" + (getattr(v, "id", "") or ""),
})
log("ytscrape search : " + str(len(resultats)) + " resultats pour '" + query + "'")
return {"resultats": resultats, "total": len(resultats), "query": query, "source": "ytscrape"}
except Exception as e:
log("ytscrape erreur : " + str(e)[:150])
return {"erreur": str(e)[:150], "code": 0}


def yt_video_scrape(video_id):
"""Details d'une video via ytscrape."""
if not YTSCRAPE_OK:
return {"erreur": "ytscrape non installe", "code": 0}

try:
with YouTube(language="fr", region="CA") as yt:
url = "https://www.youtube.com/watch?v=" + video_id
v = yt.video(url)
return {
"video_id": video_id,
"titre": getattr(v, "title", "") or "",
"description": getattr(v, "description", "") or "",
"chaine_nom": getattr(v, "channel", {}).get("name", "") if hasattr(v, "channel") and isinstance(getattr(v, "channel"), dict) else getattr(v, "channel", "") or "",
"vues": int(getattr(v, "views", 0) or 0),
"duree_iso": str(getattr(v, "length_seconds", 0) or 0),
"thumbnail": getattr(v, "thumbnail", "") or "",
"url": url,
"embed": "https://www.youtube.com/embed/" + video_id,
}
except Exception as e:
log("ytscrape video erreur : " + str(e)[:150])
return {"erreur": str(e)[:150], "code": 0}


# ===============================================================
# BASE DE DONNEES
# ===============================================================

def init_db():
conn = sqlite3.connect(DB_PATH, timeout=30)
c = conn.cursor()

c.execute("""CREATE TABLE IF NOT EXISTS videos (
id TEXT PRIMARY KEY,
titre TEXT,
description TEXT,
chaine_id TEXT,
chaine_nom TEXT,
duree INTEGER,
vues INTEGER DEFAULT 0,
likes INTEGER DEFAULT 0,
commentaires INTEGER DEFAULT 0,
tags TEXT,
categorie TEXT,
fichier TEXT,
thumbnail TEXT,
largeur INTEGER,
hauteur INTEGER,
codec TEXT,
timestamp REAL,
visibilite TEXT DEFAULT 'public'
)""")

c.execute("""CREATE TABLE IF NOT EXISTS chaines (
id TEXT PRIMARY KEY,
nom TEXT,
description TEXT,
avatar TEXT,
banniere TEXT,
abonnes INTEGER DEFAULT 0,
videos INTEGER DEFAULT 0,
timestamp REAL
)""")

c.execute("""CREATE TABLE IF NOT EXISTS abonnements (
user_id TEXT,
chaine_id TEXT,
timestamp REAL,
PRIMARY KEY (user_id, chaine_id)
)""")

c.execute("""CREATE TABLE IF NOT EXISTS historique (
id INTEGER PRIMARY KEY AUTOINCREMENT,
user_id TEXT,
video_id TEXT,
timestamp REAL,
duree_vue INTEGER DEFAULT 0
)""")

c.execute("""CREATE TABLE IF NOT EXISTS likes (
user_id TEXT,
video_id TEXT,
type TEXT,
timestamp REAL,
PRIMARY KEY (user_id, video_id)
)""")

c.execute("""CREATE TABLE IF NOT EXISTS youtube_imports (
video_id TEXT PRIMARY KEY,
titre TEXT,
chaine_nom TEXT,
embed_url TEXT,
imported_at REAL
)""")

c.execute("""CREATE VIRTUAL TABLE IF NOT EXISTS videos_fts
USING fts5(video_id, titre, description, tags, chaine)""")

c.execute("CREATE INDEX IF NOT EXISTS idx_videos_chaine ON videos(chaine_id)")
c.execute("CREATE INDEX IF NOT EXISTS idx_videos_timestamp ON videos(timestamp)")
c.execute("CREATE INDEX IF NOT EXISTS idx_hist_user ON historique(user_id)")
c.execute("CREATE INDEX IF NOT EXISTS idx_abos_user ON abonnements(user_id)")
c.execute("CREATE INDEX IF NOT EXISTS idx_yt_imports ON youtube_imports(imported_at)")

conn.commit()
conn.close()
log("DB : " + DB_PATH)


def get_db():
conn = sqlite3.connect(DB_PATH, check_same_thread=False, timeout=30)
conn.row_factory = sqlite3.Row
try:
conn.execute("PRAGMA journal_mode = WAL")
conn.execute("PRAGMA synchronous = NORMAL")
except Exception:
pass
return conn


# ===============================================================
# IMPORT YOUTUBE (ytscrape)
# ===============================================================

def importer_youtube(video_id):
details = yt_video_scrape(video_id)
if "erreur" in details:
return details

embed_url = details["embed"]
conn = get_db()
try:
c = conn.cursor()
c.execute("""INSERT OR REPLACE INTO youtube_imports
(video_id, titre, chaine_nom, embed_url, imported_at)
VALUES (?, ?, ?, ?, ?)""",
(video_id, details["titre"], details["chaine_nom"], embed_url, time.time()))
conn.commit()
finally:
conn.close()

log("YouTube importe : " + video_id + " - " + details["titre"][:60])
return {
"ok": True,
"video_id": video_id,
"titre": details["titre"],
"chaine_nom": details["chaine_nom"],
"embed_url": embed_url,
"details": details,
}


def lister_imports():
conn = get_db()
try:
c = conn.cursor()
c.execute("SELECT * FROM youtube_imports ORDER BY imported_at DESC LIMIT 100")
return [dict(r) for r in c.fetchall()]
finally:
conn.close()


# ===============================================================
# ROUTING
# ===============================================================

ROUTES = [
(r"^/$", "accueil"),
(r"^/watch/([a-zA-Z0-9_-]{11})$", "watch"),
(r"^/feed/(trending|subscriptions|history|explore)$", "feed"),
(r"^/channel/([a-zA-Z0-9_-]+)$", "channel"),
(r"^/search$", "search"),
(r"^/shorts/([a-zA-Z0-9_-]{11})$", "shorts"),
(r"^/upload$", "upload"),
(r"^/studio$", "studio"),
]


def router(path):
for pattern, nom in ROUTES:
m = re.match(pattern, path)
if m:
return {"nom": nom, "params": list(m.groups()), "match": m.group(0)}
return {"nom": "404", "params": [], "match": path}


# ===============================================================
# STOCKAGE
# ===============================================================

def stocker_video(chemin_source, dossier_dest=VIDEOS_DIR):
h = hashlib.sha256()
with open(chemin_source, "rb") as f:
while True:
chunk = f.read(65536)
if not chunk:
break
h.update(chunk)
hash_id = h.hexdigest()[:16]
ext = os.path.splitext(chemin_source)[1] or ".mp4"
dest = os.path.join(dossier_dest, hash_id + ext)
if not os.path.exists(dest):
try:
os.rename(chemin_source, dest)
except OSError:
import shutil
shutil.copy2(chemin_source, dest)
return {"id": hash_id, "chemin": dest, "taille": os.path.getsize(dest)}


# ===============================================================
# API LOCALE
# ===============================================================

def handle_browse(params):
feed = params.get("feed", "accueil")
conn = get_db()
try:
c = conn.cursor()
if feed == "trending":
c.execute("SELECT * FROM videos WHERE visibilite = 'public' ORDER BY vues DESC LIMIT 50")
else:
c.execute("SELECT * FROM videos WHERE visibilite = 'public' ORDER BY timestamp DESC LIMIT 50")
videos = [dict(r) for r in c.fetchall()]
finally:
conn.close()
return {"contents": videos, "context": {"feed": feed}, "total": len(videos)}


def handle_player(video_id):
conn = get_db()
try:
c = conn.cursor()
c.execute("SELECT * FROM videos WHERE id = ?", (video_id,))
row = c.fetchone()
if not row:
return {"erreur": "video non trouvee"}
video = dict(row)
c.execute("UPDATE videos SET vues = vues + 1 WHERE id = ?", (video_id,))
conn.commit()
finally:
conn.close()

return {
"streamingData": {
"url": "/videos/" + video["fichier"].split("/")[-1],
"codec": video.get("codec", "unknown"),
"width": video.get("largeur", 0),
"height": video.get("hauteur", 0),
},
"videoDetails": {
"videoId": video["id"],
"title": video["titre"],
"lengthSeconds": video.get("duree", 0),
"author": video.get("chaine_nom", ""),
"viewCount": video.get("vues", 0),
},
}


def handle_search(query, user_id=None):
conn = get_db()
try:
c = conn.cursor()
if query:
try:
c.execute("""SELECT video_id FROM videos_fts
WHERE videos_fts MATCH ? ORDER BY rank LIMIT 50""", (query,))
ids = [r["video_id"] for r in c.fetchall()]
except Exception:
ids = []
if not ids:
c.execute("SELECT id FROM videos WHERE titre LIKE ? OR description LIKE ? LIMIT 50",
("%" + query + "%", "%" + query + "%"))
ids = [r["id"] for r in c.fetchall()]
else:
c.execute("SELECT id FROM videos ORDER BY vues DESC LIMIT 50")
ids = [r["id"] for r in c.fetchall()]

videos = []
for vid in ids:
c.execute("SELECT * FROM videos WHERE id = ?", (vid,))
row = c.fetchone()
if row:
videos.append(dict(row))
finally:
conn.close()
return {"results": videos, "query": query, "total": len(videos)}


def handle_next(video_id, user_id=None):
conn = get_db()
try:
c = conn.cursor()
c.execute("SELECT chaine_id, tags FROM videos WHERE id = ?", (video_id,))
row = c.fetchone()
if not row:
return {"recommendations": []}
chaine_id = row["chaine_id"]
tags = (row["tags"] or "").split(",")

recommandations = []
if chaine_id:
c.execute("SELECT * FROM videos WHERE chaine_id = ? AND id != ? LIMIT 20", (chaine_id, video_id))
recommandations.extend([dict(r) for r in c.fetchall()])

for tag in tags[:3]:
tag = tag.strip()
if tag:
c.execute("SELECT * FROM videos WHERE tags LIKE ? AND id != ? LIMIT 10",
("%" + tag + "%", video_id))
for r in c.fetchall():
v = dict(r)
if v not in recommandations:
recommandations.append(v)

if len(recommandations) < 20:
c.execute("SELECT * FROM videos WHERE id != ? ORDER BY vues DESC LIMIT 20", (video_id,))
for r in c.fetchall():
v = dict(r)
if v not in recommandations:
recommandations.append(v)
finally:
conn.close()

return {"recommendations": recommandations[:30]}


def handle_guide(user_id=None):
conn = get_db()
try:
c = conn.cursor()
c.execute("SELECT * FROM chaines ORDER BY abonnes DESC LIMIT 30")
chaines = [dict(r) for r in c.fetchall()]
finally:
conn.close()

items = [
{"nom": "Accueil", "url": "/", "icone": "home"},
{"nom": "Tendances", "url": "/feed/trending", "icone": "fire"},
{"nom": "Abonnements", "url": "/feed/subscriptions", "icone": "subs"},
{"nom": "Historique", "url": "/feed/history", "icone": "history"},
{"nom": "Explorer", "url": "/feed/explore", "icone": "explore"},
{"nom": "YouTube", "url": "/youtube", "icone": "youtube"},
{"nom": "Studio", "url": "/studio", "icone": "studio"},
]

for ch in chaines:
items.append({
"nom": ch["nom"],
"url": "/channel/" + ch["id"],
"icone": "channel",
"avatar": ch.get("avatar", ""),
})

return {"items": items, "chaines": chaines}


def handle_channel(chaine_id):
conn = get_db()
try:
c = conn.cursor()
c.execute("SELECT * FROM chaines WHERE id = ?", (chaine_id,))
row = c.fetchone()
chaine = dict(row) if row else {"id": chaine_id, "nom": chaine_id}

c.execute("SELECT * FROM videos WHERE chaine_id = ? ORDER BY timestamp DESC", (chaine_id,))
videos = [dict(r) for r in c.fetchall()]
finally:
conn.close()

return {"chaine": chaine, "videos": videos, "total_videos": len(videos)}


# ===============================================================
# AUTH
# ===============================================================

def create_session(user_id):
payload = user_id + "|" + str(int(time.time()))
sig = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()
return payload + "|" + sig


def verify_session(cookie):
if not cookie:
return None
try:
user_id, ts, sig = cookie.rsplit("|", 2)
payload = user_id + "|" + ts
expected = hmac.new(SECRET, payload.encode(), hashlib.sha256).hexdigest()
if not hmac.compare_digest(sig, expected):
return None
if int(time.time()) - int(ts) > 86400 * 7:
return None
return user_id
except Exception:
return None


# ===============================================================
# RECOMMANDATION
# ===============================================================

def score_video(video, user_signaux):
score = 0.0
score += video.get("vues", 0) * 0.001
score += video.get("likes", 0) * 0.01
score += video.get("commentaires", 0) * 0.02
recence = max(0, 30 - int((time.time() - video.get("timestamp", 0)) / 86400))
score += recence * 0.5
if video.get("chaine_id") in user_signaux.get("abonnements", []):
score += 100
tags = (video.get("tags") or "").split(",")
for tag in tags:
tag = tag.strip()
if tag in user_signaux.get("interets", []):
score += 20
score += math.log1p(video.get("duree_vue_moyenne", 0)) * 5
return score


def recommander(videos, user_signaux, limite=20):
scored = [(v, score_video(v, user_signaux)) for v in videos]
scored.sort(key=lambda x: -x[1])
return [v for v, _ in scored[:limite]]


def get_user_signaux(user_id):
if not user_id:
return {"abonnements": [], "interets": [], "historique": []}
conn = get_db()
try:
c = conn.cursor()
c.execute("SELECT chaine_id FROM abonnements WHERE user_id = ?", (user_id,))
abos = [r["chaine_id"] for r in c.fetchall()]

c.execute("""SELECT v.tags FROM historique h
JOIN videos v ON v.id = h.video_id
WHERE h.user_id = ? LIMIT 100""", (user_id,))
interets = []
for r in c.fetchall():
for tag in (r["tags"] or "").split(","):
tag = tag.strip()
if tag and tag not in interets:
interets.append(tag)

c.execute("SELECT video_id FROM historique WHERE user_id = ? ORDER BY timestamp DESC LIMIT 50", (user_id,))
hist = [r["video_id"] for r in c.fetchall()]
finally:
conn.close()
return {"abonnements": abos, "interets": interets, "historique": hist}


# ===============================================================
# HTML COMPLET
# ===============================================================

HTML = r"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>NexuTube</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,system-ui,sans-serif;background:#0f0f0f;color:#fff;min-height:100vh}
.header{position:sticky;top:0;background:#0f0f0f;border-bottom:1px solid #272727;padding:10px 16px;display:flex;align-items:center;gap:16px;z-index:100;flex-wrap:wrap}
.logo{font-size:20px;font-weight:700;background:linear-gradient(135deg,#ff0033,#ff00c8);-webkit-background-clip:text;-webkit-text-fill-color:transparent;letter-spacing:-1px;cursor:pointer}
.badge{background:rgba(255,0,200,0.15);color:#ff00c8;font-size:10px;padding:3px 10px;border-radius:999px;font-weight:700;letter-spacing:1px}
.search-bar{flex:1;max-width:600px;display:flex;min-width:250px}
.search-bar input{flex:1;padding:8px 14px;background:#121212;border:1px solid #303030;border-radius:20px 0 0 20px;color:#fff;font-size:14px;outline:none}
.search-bar button{padding:8px 20px;background:#ff00c8;border:none;border-radius:0 20px 20px 0;color:#fff;font-weight:700;cursor:pointer}
.nav{display:flex;gap:8px;padding:8px 16px;overflow-x:auto;background:#0f0f0f;border-bottom:1px solid #272727}
.nav a{padding:6px 14px;background:#272727;border-radius:16px;color:#fff;text-decoration:none;font-size:13px;white-space:nowrap;transition:all 0.2s}
.nav a:hover,.nav a.active{background:#fff;color:#000}
.container{display:grid;grid-template-columns:220px 1fr;gap:20px;padding:20px;max-width:1600px;margin:0 auto}
@media(max-width:900px){.container{grid-template-columns:1fr;padding:10px}}
.sidebar{background:#181818;border-radius:12px;padding:12px;height:fit-content;position:sticky;top:80px}
.sidebar-item{padding:10px 14px;border-radius:8px;cursor:pointer;margin-bottom:4px;font-size:14px;transition:all 0.2s}
.sidebar-item:hover{background:#272727}
.sidebar-item.active{background:#303030}
.chaine-info{display:flex;align-items:center;gap:10px;padding:8px}
.chaine-avatar{width:32px;height:32px;border-radius:50%;background:linear-gradient(135deg,#ff0033,#ff00c8);display:flex;align-items:center;justify-content:center;font-weight:700;color:#fff;font-size:14px}
.content{min-height:80vh}
.video-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px}
.video-card{background:#181818;border-radius:12px;overflow:hidden;cursor:pointer;transition:transform 0.2s}
.video-card:hover{transform:translateY(-4px)}
.video-thumb{aspect-ratio:16/9;background:linear-gradient(135deg,#272727,#1a1a1a);display:flex;align-items:center;justify-content:center;font-size:40px;color:#555;position:relative;overflow:hidden}
.video-thumb img{width:100%;height:100%;object-fit:cover}
.video-thumb .duree{position:absolute;bottom:8px;right:8px;background:rgba(0,0,0,0.8);padding:2px 6px;border-radius:4px;font-size:11px;font-weight:600}
.video-thumb .play{position:absolute;inset:0;background:rgba(0,0,0,0.3);display:flex;align-items:center;justify-content:center;font-size:48px;opacity:0;transition:opacity 0.2s}
.video-card:hover .video-thumb .play{opacity:1}
.video-info{padding:12px}
.video-titre{font-size:14px;font-weight:600;margin-bottom:6px;line-height:1.4;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.video-meta{font-size:12px;color:#aaa}
.video-meta span{display:block;margin-bottom:2px}
.watch-player{background:#000;border-radius:12px;overflow:hidden;margin-bottom:16px}
.watch-player video{width:100%;display:block;max-height:70vh;background:#000}
.embed-frame{width:100%;max-width:900px;margin:20px auto;aspect-ratio:16/9;border-radius:12px;overflow:hidden;background:#000}
.embed-frame iframe{width:100%;height:100%;border:0}
.watch-title{font-size:20px;font-weight:700;margin-bottom:8px}
.watch-channel{display:flex;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid #272727;margin-bottom:12px}
.watch-actions{display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap}
.watch-actions button{padding:8px 16px;background:#272727;border:none;border-radius:20px;color:#fff;cursor:pointer;font-size:13px;transition:all 0.2s}
.watch-actions button:hover{background:#303030}
.watch-actions button.active{background:#fff;color:#000}
.shorts-view{height:80vh;display:flex;justify-content:center;align-items:center;background:#000;border-radius:12px;overflow:hidden}
.shorts-view video{max-height:80vh;max-width:100%;border-radius:12px}
.upload-zone{border:2px dashed #303030;border-radius:12px;padding:60px 20px;text-align:center;cursor:pointer;transition:all 0.2s}
.upload-zone:hover{border-color:#ff00c8;background:rgba(255,0,200,0.05)}
.upload-zone input{display:none}
.upload-label{font-size:16px;font-weight:700;color:#ff00c8;margin-bottom:8px}
.form-group{margin-bottom:16px}
.form-group label{display:block;font-size:12px;color:#aaa;margin-bottom:6px;text-transform:uppercase;letter-spacing:1px}
.form-group input,.form-group textarea{width:100%;padding:10px 14px;background:#121212;border:1px solid #303030;border-radius:8px;color:#fff;font-size:14px;outline:none;font-family:inherit}
.form-group input:focus,.form-group textarea:focus{border-color:#ff00c8}
.btn{padding:10px 24px;background:linear-gradient(135deg,#ff0033,#ff00c8);border:none;border-radius:20px;color:#fff;font-weight:700;cursor:pointer;font-size:14px}
.btn:hover{opacity:0.9}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:20px}
.stat{background:#181818;border-radius:10px;padding:14px}
.stat-lbl{color:#888;font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:4px}
.stat-val{color:#ff00c8;font-size:20px;font-weight:700;font-family:ui-monospace,monospace}
.footer{text-align:center;color:#444;font-size:11px;margin-top:40px;padding:20px;font-family:ui-monospace,monospace}
.loading{text-align:center;padding:40px;color:#888}
.empty{text-align:center;padding:60px 20px;color:#666}
.status{padding:8px 16px;background:#181818;border-bottom:1px solid #272727;font-size:12px;color:#888;font-family:ui-monospace,monospace}
.status.ok{color:#00ff88}
.status.ko{color:#ff4444}
</style>
</head>
<body>

<div class="header">
<div class="logo" onclick="navigate('/')">NexuTube</div>
<div class="badge">v__V__</div>
<div class="search-bar">
<input id="search-input" placeholder="Rechercher (local + YouTube)..." onkeydown="if(event.key==='Enter')rechercher()">
<button onclick="rechercher()">🔍</button>
</div>
</div>

<div class="status __STATUS_CLASS__" id="status">__STATUS_TEXT__</div>

<div class="nav" id="nav-top"></div>

<div class="container">
<div class="sidebar" id="sidebar"></div>
<div class="content" id="content">
<div class="loading">Chargement...</div>
</div>
</div>

<div class="footer">NexuTube v__V__ - Aissa Mohammedi (DGK) - NEXUS-OPEN-2.0</div>

<script>
var USER_ID = localStorage.getItem('nexutube_user') || 'user_' + Math.random().toString(36).slice(2, 10);
localStorage.setItem('nexutube_user', USER_ID);

function esc(s){return String(s||'').replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
function fmtDuree(sec){if(!sec)return '0:00';var m=Math.floor(sec/60);var s=sec%60;return m+':'+(s<10?'0':'')+s;}
function fmtVues(n){if(n>=1000000)return (n/1000000).toFixed(1)+'M';if(n>=1000)return (n/1000).toFixed(1)+'K';return n;}

function navigate(path){
history.pushState({}, '', path);
router(path);
}
window.addEventListener('popstate', function(){ router(location.pathname); });

async function chargerGuide(){
try {
var r = await fetch('/nexutube/v1/guide?user_id=' + USER_ID);
var d = await r.json();
var navHtml = '<a href="#" onclick="navigate(\'/\');return false">Accueil</a>';
navHtml += '<a href="#" onclick="navigate(\'/feed/trending\');return false">Tendances</a>';
navHtml += '<a href="#" onclick="navigate(\'/feed/subscriptions\');return false">Abonnements</a>';
navHtml += '<a href="#" onclick="navigate(\'/feed/history\');return false">Historique</a>';
navHtml += '<a href="#" onclick="navigate(\'/feed/explore\');return false">Explorer</a>';
navHtml += '<a href="#" onclick="navigate(\'/youtube\');return false">YouTube</a>';
navHtml += '<a href="#" onclick="navigate(\'/upload\');return false">Uploader</a>';
navHtml += '<a href="#" onclick="navigate(\'/studio\');return false">Studio</a>';
document.getElementById('nav-top').innerHTML = navHtml;
} catch(e) {}
}

async function router(path){
var content = document.getElementById('content');
content.innerHTML = '<div class="loading">Chargement...</div>';
if(path === '/' || path === '') return accueil();
if(path.match(/^\/watch\/([a-zA-Z0-9_-]{11})$/)) return watch(path.match(/^\/watch\/([a-zA-Z0-9_-]{11})$/)[1]);
if(path.match(/^\/feed\/(trending|subscriptions|history|explore)$/)) return feed(path.match(/^\/feed\/(\w+)$/)[1]);
if(path.match(/^\/channel\/([a-zA-Z0-9_-]+)$/)) return chaine(path.match(/^\/channel\/([a-zA-Z0-9_-]+)$/)[1]);
if(path === '/search') return recherche_page();
if(path.match(/^\/shorts\/([a-zA-Z0-9_-]{11})$/)) return shorts(path.match(/^\/shorts\/([a-zA-Z0-9_-]{11})$/)[1]);
if(path === '/upload') return upload_page();
if(path === '/studio') return studio_page();
if(path === '/youtube') return youtube_page();
content.innerHTML = '<div class="empty"><h2>404</h2><p>Page non trouvee</p></div>';
}

async function accueil(){
try {
var r = await fetch('/nexutube/v1/browse?feed=recent');
var d = await r.json();
afficherGrille(d.contents || [], 'Accueil');
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

async function feed(type){
try {
var r = await fetch('/nexutube/v1/browse?feed=' + type);
var d = await r.json();
var titre = {trending: 'Tendances', subscriptions: 'Abonnements', history: 'Historique', explore: 'Explorer'}[type] || type;
afficherGrille(d.contents || [], titre);
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

function afficherGrille(videos, titre){
var html = '<h2 style="margin-bottom:16px;font-size:20px">' + esc(titre) + '</h2>';
if(!videos.length){
html += '<div class="empty"><p>Aucune video.</p><p style="margin-top:12px"><button class="btn" onclick="navigate(\'/upload\')">Uploader</button></p></div>';
document.getElementById('content').innerHTML = html;
return;
}
html += '<div class="video-grid">';
videos.forEach(function(v){
html += '<div class="video-card" onclick="navigate(\'/watch/' + esc(v.id) + '\')">';
html += '<div class="video-thumb">🎬';
if(v.duree) html += '<span class="duree">' + fmtDuree(v.duree) + '</span>';
html += '</div>';
html += '<div class="video-info">';
html += '<div class="video-titre">' + esc(v.titre || 'Sans titre') + '</div>';
html += '<div class="video-meta">';
html += '<span>' + esc(v.chaine_nom || 'Inconnue') + '</span>';
html += '<span>' + fmtVues(v.vues || 0) + ' vues</span>';
html += '</div></div></div>';
});
html += '</div>';
document.getElementById('content').innerHTML = html;
}

async function watch(videoId){
try {
var r = await fetch('/nexutube/v1/player?video_id=' + videoId);
var d = await r.json();
if(d.erreur){ document.getElementById('content').innerHTML = '<div class="empty">Video non trouvee</div>'; return; }

var vd = d.videoDetails || {};
var sd = d.streamingData || {};

var html = '<div class="watch-player"><video id="nexu-player" controls playsinline autoplay><source src="' + esc(sd.url || '') + '" type="video/mp4"></video></div>';
html += '<h1 class="watch-title">' + esc(vd.title || '') + '</h1>';
html += '<div class="watch-channel"><div class="chaine-avatar">' + esc((vd.author || '?')[0].toUpperCase()) + '</div>';
html += '<div><div style="font-weight:600">' + esc(vd.author || '') + '</div>';
html += '<div style="font-size:12px;color:#aaa">' + fmtVues(vd.viewCount || 0) + ' vues</div></div></div>';
html += '<div class="watch-actions">';
html += '<button onclick="liker(\'' + videoId + '\',\'like\',this)">👍 Like</button>';
html += '<button onclick="liker(\'' + videoId + '\',\'dislike\',this)">👎 Dislike</button>';
html += '<button onclick="partager(\'' + videoId + '\')">🔗 Partager</button>';
html += '</div>';
document.getElementById('content').innerHTML = html;

var r2 = await fetch('/nexutube/v1/next?video_id=' + videoId);
var d2 = await r2.json();
var reco = d2.recommendations || [];
if(reco.length){
var html2 = '<h2 style="margin:24px 0 16px;font-size:18px">A suivre</h2><div class="video-grid">';
reco.forEach(function(v){
if(v.id === videoId) return;
html2 += '<div class="video-card" onclick="navigate(\'/watch/' + esc(v.id) + '\')">';
html2 += '<div class="video-thumb">🎬';
if(v.duree) html2 += '<span class="duree">' + fmtDuree(v.duree) + '</span>';
html2 += '</div>';
html2 += '<div class="video-info">';
html2 += '<div class="video-titre">' + esc(v.titre || '') + '</div>';
html2 += '<div class="video-meta"><span>' + esc(v.chaine_nom || '') + '</span></div>';
html2 += '</div></div>';
});
html2 += '</div>';
document.getElementById('content').innerHTML += html2;
}
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

async function chaine(chaineId){
try {
var r = await fetch('/nexutube/v1/channel?channel_id=' + chaineId);
var d = await r.json();
var ch = d.chaine || {};
var html = '<div class="watch-channel"><div class="chaine-avatar" style="width:64px;height:64px;font-size:24px">' + esc((ch.nom || '?')[0].toUpperCase()) + '</div>';
html += '<div><h2>' + esc(ch.nom || chaineId) + '</h2><div style="font-size:12px;color:#aaa">' + (ch.abonnes || 0) + ' abonnes</div></div></div>';
document.getElementById('content').innerHTML = html;
afficherGrille(d.videos || [], '');
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

async function rechercher(){
var q = document.getElementById('search-input').value.trim();
if(!q) return;
try {
var r = await fetch('/nexutube/v1/search?q=' + encodeURIComponent(q));
var d = await r.json();
afficherGrille(d.results || [], 'Resultats locaux : ' + q);
var r2 = await fetch('/youtube/search?q=' + encodeURIComponent(q) + '&max=20');
var d2 = await r2.json();
if(d2.erreur){
var htmlErr = '<h2 style="margin:32px 0 16px;font-size:18px;color:#ff00c8">YouTube</h2>';
htmlErr += '<div class="empty">' + esc(d2.erreur) + '</div>';
document.getElementById('content').innerHTML += htmlErr;
return;
}
if(d2.resultats && d2.resultats.length){
var html = '<h2 style="margin:32px 0 16px;font-size:18px;color:#ff00c8">YouTube (' + d2.resultats.length + ')</h2><div class="video-grid">';
d2.resultats.forEach(function(v){
html += '<div class="video-card" onclick="lecteurYT(\'' + esc(v.video_id) + '\')">';
html += '<div class="video-thumb">';
if(v.thumbnail) html += '<img src="' + esc(v.thumbnail) + '" loading="lazy" alt="">';
html += '<div class="play">▶</div></div>';
html += '<div class="video-info">';
html += '<div class="video-titre">' + esc(v.titre) + '</div>';
html += '<div class="video-meta"><span>' + esc(v.chaine_nom) + '</span>';
if(v.duree) html += '<span>' + fmtDuree(v.duree) + '</span>';
html += '</div></div></div>';
});
html += '</div>';
document.getElementById('content').innerHTML += html;
}
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

function lecteurYT(videoId){
var html = '<button onclick="history.back()" style="margin-bottom:16px;padding:8px 16px;background:#272727;border:none;border-radius:16px;color:#fff;cursor:pointer">← Retour</button>';
html += '<div class="embed-frame"><iframe src="https://www.youtube.com/embed/' + esc(videoId) + '?autoplay=1" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></div>';
document.getElementById('content').innerHTML = html;
}

async function youtube_page(){
var html = '<h2 style="margin-bottom:16px">YouTube (sans cle API)</h2>';
html += '<div class="status ok">ytscrape : ' + (window.YTSCRAPE_OK ? 'disponible' : 'indisponible') + '</div>';
html += '<div class="form-group" style="margin-top:20px"><label>Rechercher sur YouTube</label>';
html += '<input id="yt-q" placeholder="Mot-cle..." onkeydown="if(event.key===\'Enter\')yt_search()"></div>';
html += '<button class="btn" onclick="yt_search()">Chercher</button>';
document.getElementById('content').innerHTML = html;
}

async function yt_search(){
var q = document.getElementById('yt-q').value.trim();
if(!q) return;
document.getElementById('content').innerHTML = '<div class="loading">Recherche YouTube...</div>';
try {
var r = await fetch('/youtube/search?q=' + encodeURIComponent(q) + '&max=25');
var d = await r.json();
if(d.erreur){ document.getElementById('content').innerHTML = '<div class="empty">Erreur : ' + esc(d.erreur) + '</div>'; return; }
var html = '<h2 style="margin-bottom:16px">YouTube : ' + esc(q) + ' (' + (d.resultats||[]).length + ')</h2><div class="video-grid">';
(d.resultats || []).forEach(function(v){
html += '<div class="video-card" onclick="lecteurYT(\'' + esc(v.video_id) + '\')">';
html += '<div class="video-thumb">';
if(v.thumbnail) html += '<img src="' + esc(v.thumbnail) + '" loading="lazy" alt="">';
html += '<div class="play">▶</div></div>';
html += '<div class="video-info">';
html += '<div class="video-titre">' + esc(v.titre) + '</div>';
html += '<div class="video-meta"><span>' + esc(v.chaine_nom) + '</span>';
if(v.duree) html += '<span>' + fmtDuree(v.duree) + '</span>';
html += '</div></div></div>';
});
html += '</div>';
document.getElementById('content').innerHTML = html;
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

async function recherche_page(){
document.getElementById('content').innerHTML = '<div class="empty">Tape une recherche en haut</div>';
}

async function shorts(videoId){
try {
var r = await fetch('/nexutube/v1/player?video_id=' + videoId);
var d = await r.json();
if(d.erreur){ document.getElementById('content').innerHTML = '<div class="empty">Video non trouvee</div>'; return; }
var html = '<div class="shorts-view"><video controls playsinline autoplay><source src="' + esc(d.streamingData.url) + '" type="video/mp4"></video></div>';
document.getElementById('content').innerHTML = html;
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

async function upload_page(){
var html = '<h2 style="margin-bottom:20px">Uploader une video</h2>';
html += '<div class="upload-zone" onclick="document.getElementById(\'file-input\').click()">';
html += '<input type="file" id="file-input" accept="video/*" onchange="uploadFichier(this)">';
html += '<div class="upload-label">Clique pour choisir un fichier</div>';
html += '<div style="color:#888;font-size:12px">MP4, WebM, MKV, MOV</div></div>';
document.getElementById('content').innerHTML = html;
}

async function uploadFichier(input){
if(!input.files || !input.files[0]) return;
var file = input.files[0];
document.getElementById('content').innerHTML = '<div class="loading">Upload en cours : ' + esc(file.name) + '</div>';
var fd = new FormData();
fd.append('file', file);
try {
var r = await fetch('/nexutube/v1/upload', {method:'POST', body: fd});
var d = await r.json();
if(d.ok) { alert('Video uploadee ! ID : ' + d.id); navigate('/watch/' + d.id); }
else { alert('Erreur : ' + (d.erreur || '?')); }
} catch(e) { alert('Erreur reseau'); }
}

async function studio_page(){
try {
var r = await fetch('/youtube/imports');
var d = await r.json();
var html = '<h2>Studio</h2><h3 style="margin:20px 0 12px;font-size:16px;color:#ff00c8">Imports YouTube</h3>';
var imports = d.imports || [];
if(!imports.length){ html += '<div class="empty">Aucun import YouTube</div>'; }
else {
html += '<table style="width:100%;border-collapse:collapse;font-size:13px"><tr style="color:#ff00c8"><th style="text-align:left;padding:8px;border-bottom:1px solid #272727">Titre</th><th style="text-align:left;padding:8px;border-bottom:1px solid #272727">Chaine</th><th style="text-align:left;padding:8px;border-bottom:1px solid #272727">Date</th></tr>';
imports.forEach(function(i){
html += '<tr><td style="padding:8px;border-bottom:1px solid #272727">' + esc(i.titre) + '</td>';
html += '<td style="padding:8px;border-bottom:1px solid #272727">' + esc(i.chaine_nom) + '</td>';
html += '<td style="padding:8px;border-bottom:1px solid #272727">' + new Date(i.imported_at * 1000).toLocaleDateString() + '</td></tr>';
});
html += '</table>';
}
document.getElementById('content').innerHTML = html;
} catch(e) { document.getElementById('content').innerHTML = '<div class="empty">Erreur reseau</div>'; }
}

async function liker(videoId, type, btn){
try {
var r = await fetch('/nexutube/v1/like', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({video_id: videoId, type: type, user_id: USER_ID})});
var d = await r.json();
if(d.ok && btn) btn.classList.toggle('active');
} catch(e) {}
}

function partager(videoId){
var url = location.origin + '/watch/' + videoId;
if(navigator.share){ navigator.share({url: url}); }
else if(navigator.clipboard){ navigator.clipboard.writeText(url).then(function(){ alert('Lien copie !'); }); }
else { prompt('Copie ce lien :', url); }
}

window.YTSCRAPE_OK = __YTSCRAPE_OK__;
chargerGuide();
router(location.pathname);
</script>
</body>
</html>"""


# ===============================================================
# SERVEUR HTTP
# ===============================================================

class Handler(BaseHTTPRequestHandler):
def log_message(self, fmt, *args):
pass

def _send(self, code, content, ctype="application/json"):
try:
self.send_response(code)
self.send_header("Content-Type", ctype + "; charset=utf-8")
self.send_header("Access-Control-Allow-Origin", "*")
self.send_header("Cache-Control", "no-cache")
self.send_header("Content-Length", str(len(content)))
self.end_headers()
self.wfile.write(content)
except (BrokenPipeError, ConnectionResetError):
pass

def _json(self, obj, code=200):
self._send(code, json.dumps(obj, ensure_ascii=False, default=str).encode())

def do_GET(self):
parsed = urllib.parse.urlparse(self.path)
path = parsed.path
params = urllib.parse.parse_qs(parsed.query)

if path in ("/", "/index.html"):
status_class = "ok" if YTSCRAPE_OK else "ko"
status_text = "YouTube via ytscrape : actif" if YTSCRAPE_OK else "ytscrape non installe - pip install ytscrape"
html = HTML.replace("__V__", VERSION)
html = html.replace("__STATUS_CLASS__", status_class).replace("__STATUS_TEXT__", status_text)
html = html.replace("__YTSCRAPE_OK__", "true" if YTSCRAPE_OK else "false")
return self._send(200, html.encode("utf-8"), "text/html")

if path == "/nexutube/v1/browse":
return self._json(handle_browse(params))
if path == "/nexutube/v1/player":
vid = params.get("video_id", [""])[0]
return self._json(handle_player(vid) if vid else {"erreur": "video_id manquant"})
if path == "/nexutube/v1/search":
q = params.get("q", [""])[0]
return self._json(handle_search(q))
if path == "/nexutube/v1/next":
vid = params.get("video_id", [""])[0]
return self._json(handle_next(vid) if vid else {"recommendations": []})
if path == "/nexutube/v1/guide":
uid = params.get("user_id", [""])[0]
return self._json(handle_guide(uid))
if path == "/nexutube/v1/channel":
cid = params.get("channel_id", [""])[0]
return self._json(handle_channel(cid) if cid else {"erreur": "channel_id manquant"})

if path == "/youtube/status":
return self._json({
"version": VERSION,
"auteur": AUTEUR,
"ytscrape": YTSCRAPE_OK,
})
if path == "/youtube/search":
q = params.get("q", [""])[0]
max_r = int(params.get("max", ["25"])[0])
if not q:
return self._json({"erreur": "parametre q manquant"}, 400)
return self._json(yt_search_scrape(q, max_results=max_r))
if path == "/youtube/video":
vid = params.get("video_id", [""])[0]
if not vid:
return self._json({"erreur": "video_id manquant"}, 400)
return self._json(yt_video_scrape(vid))
if path == "/youtube/imports":
return self._json({"imports": lister_imports()})

return self._json({"erreur": "not found", "path": path}, 404)

def do_POST(self):
parsed = urllib.parse.urlparse(self.path)
path = parsed.path
params = urllib.parse.parse_qs(parsed.query)

length = int(self.headers.get("Content-Length", "0") or "0")
body = b""
if length > 0:
try:
body = self.rfile.read(length)
except Exception:
body = b""

if path == "/youtube/import":
vid = params.get("video_id", [""])[0]
if not vid:
try:
data = json.loads(body.decode("utf-8", "ignore")) if body else {}
vid = data.get("video_id", "")
except Exception:
vid = ""
if not vid:
return self._json({"erreur": "video_id manquant"}, 400)
return self._json(importer_youtube(vid))

if path == "/nexutube/v1/like":
try:
data = json.loads(body.decode("utf-8", "ignore")) if body else {}
except Exception:
data = {}
vid = data.get("video_id", "")
typ = data.get("type", "like")
uid = data.get("user_id", "")
if not vid or not uid:
return self._json({"erreur": "params manquants"}, 400)
conn = get_db()
try:
c = conn.cursor()
c.execute("INSERT OR REPLACE INTO likes (user_id, video_id, type, timestamp) VALUES (?, ?, ?, ?)",
(uid, vid, typ, time.time()))
if typ == "like":
c.execute("UPDATE videos SET likes = likes + 1 WHERE id = ?", (vid,))
conn.commit()
finally:
conn.close()
return self._json({"ok": True})

return self._json({"erreur": "not found", "path": path}, 404)


class Server(ThreadingHTTPServer):
daemon_threads = True
allow_reuse_address = True


# ===============================================================
# MAIN
# ===============================================================

def main():
print("=" * 70)
print("NEXUTUBE COMPLETE v" + VERSION)
print("Version : " + VERSION)
print("Auteur : " + AUTEUR)
print("Licence : " + LICENCE)
print("=" * 70)
print("")

if YTSCRAPE_OK:
log("ytscrape detecte : YouTube sans cle API actif")
else:
log("ytscrape absent - mode local uniquement")
log("Installation : pip install ytscrape")

init_db()

print("Interface : http://localhost:" + str(PORT) + "/")
print("")
print("API locale NexuTube :")
print(" GET /nexutube/v1/browse?feed=recent")
print(" GET /nexutube/v1/player?video_id=...")
print(" GET /nexutube/v1/search?q=...")
print(" GET /nexutube/v1/next?video_id=...")
print(" GET /nexutube/v1/guide?user_id=...")
print(" GET /nexutube/v1/channel?channel_id=...")
print("")
print("YouTube via ytscrape (SANS CLE API) :")
print(" GET /youtube/status")
print(" GET /youtube/search?q=...&max=25")
print(" GET /youtube/video?video_id=...")
print(" GET /youtube/imports")
print(" POST /youtube/import?video_id=...")
print("")

if not YTSCRAPE_OK:
print(">>> ytscrape NON INSTALLE <<<")
print("Pour activer YouTube sans cle API :")
print(" pip install ytscrape")
print("")

print("Ctrl+C pour arreter")
print("")

server = Server(("0.0.0.0", PORT), Handler)
try:
server.serve_forever()
except KeyboardInterrupt:
print("")
log("Arret serveur")
server.shutdown()


if __name__ == "__main__":
main()
