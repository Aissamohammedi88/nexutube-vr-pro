--
📄 README.md

```markdown
# 🎬 NexuTube — Plateforme Vidéo Complète

**NexuTube** est une plateforme vidéo complète, légère et auto-hébergée, avec intégration **YouTube sans clé API** via `ytscrape`.

Compatible avec **a-Shell iOS**, **stdlib pure Python**, et fonctionne **sans dépendance externe** (sauf `ytscrape` en option).

---

## ✨ Fonctionnalités

### 🎥 Plateforme vidéo locale
- Upload de vidéos (MP4, WebM, MKV, MOV)
- Streaming avec lecteur HTML5 intégré
- Système de chaînes et d'abonnements
- Historique de visionnage
- Likes / Dislikes
- Recherche locale (SQLite FTS5)
- Recommandations intelligentes (scoring multi-critères)
- Shorts (format vertical)
- Studio (gestion des imports)

### 🌐 YouTube sans clé API
- Recherche YouTube via `ytscrape`
- Lecture embarquée (iframe)
- Import de vidéos YouTube dans la base locale
- Aucune clé API requise
- Fallback automatique si `ytscrape` absent

### 🧠 Système de recommandation
- Score basé sur : vues, likes, commentaires, récence, abonnements, intérêts, durée
- Algorithme pondéré (log1p, scoring multi-signaux)

### 💾 Base de données
- SQLite avec WAL mode
- Tables : `videos`, `chaines`, `abonnements`, `historique`, `likes`, `youtube_imports`
- Index FTS5 pour recherche rapide

### 🔐 Sécurité
- Sessions HMAC-SHA256 signées
- Cookie avec expiration 7 jours
- Vérification `compare_digest` (anti timing attack)

### 📱 Compatibilité
- **a-Shell iOS** (os.path uniquement)
- **stdlib pure** (aucune dépendance externe sauf `ytscrape`)
- **Multi-plateforme** : Linux, macOS, iOS, Windows

---

## 🚀 Installation

### Prérequis
- **Python 3.7+**
- **pip** (optionnel, pour `ytscrape`)

### Installation rapide

```bash
# 1. Clone le repo
git clone https://github.com/Aissamohammedi88/nexutube-vr-pro.git
cd nexutube-vr-pro

# 2. (Optionnel) Installer ytscrape pour YouTube
pip install ytscrape

# 3. Lancer
python3 main.py
```

Sur iOS (a-Shell)

```bash
# Dans a-Shell
cd ~/Documents
git clone https://github.com/Aissamohammedi88/nexutube-vr-pro.git
cd nexutube-vr-pro
python3 main.py
```

---

🎬 Utilisation

Interface Web

Ouvre ton navigateur sur :

```
http://localhost:8079/
```

Navigation

Page URL Description
Accueil / Vidéos récentes
Tendances /feed/trending Vidéos les plus vues
Abonnements /feed/subscriptions Chaînes suivies
Historique /feed/history Vidéos regardées
Explorer /feed/explore Découverte
YouTube /youtube Recherche YouTube
Upload /upload Uploader une vidéo
Studio /studio Gestion des imports
Watch /watch/{video_id} Lire une vidéo
Shorts /shorts/{video_id} Format vertical
Chaîne /channel/{channel_id} Page chaîne

---

📡 API

NexuTube (locale)

Méthode Endpoint Description
GET /nexutube/v1/browse?feed=recent Liste les vidéos
GET /nexutube/v1/player?video_id=... Détails + streaming
GET /nexutube/v1/search?q=... Recherche locale
GET /nexutube/v1/next?video_id=... Recommandations
GET /nexutube/v1/guide?user_id=... Menu latéral
GET /nexutube/v1/channel?channel_id=... Infos chaîne
POST /nexutube/v1/like Like / Dislike
POST /nexutube/v1/upload Upload vidéo

YouTube (ytscrape)

Méthode Endpoint Description
GET /youtube/status Statut ytscrape
GET /youtube/search?q=...&max=25 Recherche YouTube
GET /youtube/video?video_id=... Détails vidéo
GET /youtube/imports Liste des imports
POST /youtube/import?video_id=... Importer une vidéo

---

🗂 Structure du projet

```
nexutube-vr-pro/
├── main.py # Serveur + logique complète
├── README.md # Ce fichier
├── LICENSE # NEXUS-OPEN-2.0
└── nexutube/ # Créé automatiquement
├── videos/ # Vidéos uploadées
├── thumbnails/ # Miniatures
├── nexutube.db # Base SQLite
└── nexutube.log # Logs
```

---

🧬 Architecture

Composants principaux

Composant Rôle
Handler Serveur HTTP (GET + POST)
Server ThreadingHTTPServer (multi-thread)
init_db() Initialisation SQLite + FTS5
yt_search_scrape() Recherche YouTube via ytscrape
yt_video_scrape() Détails vidéo YouTube
importer_youtube() Import YouTube → base locale
score_video() Scoring de recommandation
recommander() Tri des recommandations
create_session() Sessions HMAC signées
verify_session() Vérification sessions

Flux de données

```
Client → Handler → Route → Traitement → JSON/HTML → Client
↓
SQLite (WAL)
↓
ytscrape (optionnel)
```

---

🎨 Interface

· Thème sombre inspiré de YouTube
· Responsive (mobile + desktop)
· Sans framework JS (Vanilla JS pur)
· Navigation SPA (history.pushState)
· Lecteur vidéo HTML5
· Iframe YouTube pour les vidéos distantes

---

🔧 Configuration

Modifier le port

Dans main.py, change :

```python
PORT = 8079 # → ton port
```

Modifier les chemins

```python
BASE = os.path.join(HOME, "Documents", "nexutube")
VIDEOS_DIR = os.path.join(BASE, "videos")
THUMBS_DIR = os.path.join(BASE, "thumbnails")
DB_PATH = os.path.join(BASE, "nexutube.db")
```

Modifier le secret HMAC

```python
SECRET = b"nexutube-secret-key-2026" # → change en prod
```

---

⚠️ Notes importantes

Dépendance optionnelle

· ytscrape est optionnel
· Sans lui → mode local uniquement
· Avec lui → YouTube sans clé API

Sécurité

· Ne pas exposer sur Internet sans reverse proxy
· Changer SECRET en production
· Activer HTTPS derrière un proxy (nginx, Caddy)

Compatibilité

· Testé sur Linux, macOS, iOS (a-Shell)
· Python 3.7+ requis
· Aucune dépendance externe en dehors de ytscrape

---

🧪 Tests rapides

Vérifier que le serveur tourne

```bash
curl http://localhost:8079/youtube/status
```

Réponse attendue :

```json
{
"version": "2.1.0",
"auteur": "Aissa Mohammedi (DGK)",
"ytscrape": true
}
```

Tester la recherche YouTube

```bash
curl "http://localhost:8079/youtube/search?q=python&max=5"
```

---

📜 Licence

NEXUS-OPEN-2.0 — Voir LICENSE

---

👤 Auteur

Aissa Mohammedi (DGK)

· 🧬 Systèmes autonomes · IA · Cloud · Sécurité
· 🔗 LinkedIn https://ca.linkedin.com/in/aissa-mohammedi-2308743b2?trk=public_post_feed-actor-name

---

🤝 Contribution

Les contributions sont les bienvenues !

1. Fork le projet
2. Crée une branche (git checkout -b feature/ma-feature)
3. Commit (git commit -m "Ajout de ma feature")
4. Push (git push origin feature/ma-feature)
5. Ouvre une Pull Request

---

⭐ Soutien

Si ce projet t'aide :

· ⭐ Mets une star sur GitHub
· 🐛 Signale les bugs
· 💡 Propose des idées
· 📢 Partage le projet

---

NexuTube — v2.1.0 — Aissa Mohammedi (DGK) — 2026

```

---

## ✅ 

| Élément | Statut |
|---------|--------|
| **Titre clair** | ✅ |
| **Description courte** | ✅ |
| **Fonctionnalités** | ✅ 7 sections |
| **Installation** | ✅ Linux/macOS/iOS |
| **Utilisation** | ✅ Tableau de navigation |
| **API complète** | ✅ 13 endpoints |
| **Structure** | ✅ Arborescence |
| **Architecture** | ✅ Composants + flux |
| **Configuration** | ✅ Port/chemins/secret |
| **Sécurité** | ✅ HMAC + WAL |
| **Tests rapides** | ✅ curl |
| **Licence** | ✅ NEXUS-OPEN-2.0 |
| **Contribution** | ✅ Guide |
| **Soutien** | ✅ Star/bugs/idées |

---
