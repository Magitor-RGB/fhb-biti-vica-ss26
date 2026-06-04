# VM-Info Dashboard – Dokumentation

**Abgabe 2 – SCHURIAN**  
Automatisierte Exoscale VM mit HTTP-Endpunkt für technische VM-Details

---

## Überblick

Diese Lösung erstellt automatisiert eine Ubuntu-VM in der Exoscale-Cloud (Wien), die über einen HTTP-Endpunkt technische Details über sich selbst ausliefert. Das Dashboard zeigt Informationen wie IP-Adresse, Memory, CPU, Storage, Kernel, Hypervisor, Dateisysteme und mehr.

```
GitHub Actions (Workflow)
        │
        ▼
  OpenTofu/Terraform
        │
        ▼
  Exoscale Cloud (at-vie-1)
        │
        ▼
  Ubuntu 24.04 LTS VM
        │  (CloudInit beim ersten Boot)
        ▼
  Python HTTP-Server → http://<VM-IP>
        │
        ▼
  VM-Info Dashboard (Browser)
```

---

## Architektur & Komponenten

### 1. Terraform/OpenTofu Konfiguration (`terraform/`)

| Datei | Zweck |
|-------|-------|
| `main.tf` | Hauptkonfiguration: VM, Security Group, Firewall-Regeln |
| `variables.tf` | Eingabevariablen (Zone, etc.) |
| `outputs.tf` | Ausgaben nach Deploy (IP, URL, Name) |
| `backend.tf` | Remote State in Exoscale Object Storage (S3-kompatibel) |
| `cloud-init.yaml` | OS-Konfiguration via CloudInit |

### 2. GitHub Actions Workflows (`.github/workflows/`)

| Datei | Zweck | Trigger |
|-------|-------|---------|
| `deploy.yml` | Erstellt die Infrastruktur | Manuell oder Push auf `main` |
| `destroy.yml` | Löscht alle Ressourcen | Nur manuell (mit Bestätigung) |

### 3. CloudInit (`terraform/cloud-init.yaml`)

CloudInit konfiguriert das OS vollautomatisch beim ersten VM-Start:
- Installiert Python3 und benötigte Pakete
- Erstellt den Python HTTP-Server unter `/opt/vminfo/server.py`
- Erstellt einen Systemd-Service (`vminfo.service`)
- Aktiviert und startet den Service

### 4. Python HTTP-Server (`server.py`, eingebettet in cloud-init.yaml)

Ein einfacher Python3-HTTP-Server der:
- Auf **Port 80** lauscht
- `/` → VM-Info HTML-Dashboard ausliefert
- `/health` → Health-Check Endpunkt (`OK`)
- Alle ~2 Sekunden aktuell Systeminformationen sammelt
- Automatisch alle 30 Sekunden im Browser neu lädt

---

## Angezeigte VM-Informationen

Das Dashboard zeigt folgende technische Details:

| Kategorie | Details |
|-----------|---------|
| **Netzwerk** | Hostname, primäre IP, öffentliche IP, alle Interfaces |
| **Betriebssystem** | OS-Version, Kernel, Architektur, Boot-Zeit, Uptime |
| **CPU** | Modell, Kerne, Threads, aktuelle Auslastung |
| **Memory/RAM** | Gesamt, verwendet, frei, verfügbar, Swap |
| **Hypervisor/Cloud** | Virtualisierungstyp, Hypervisor-Name, Instance-ID, Instance-Typ, Availability Zone |
| **Storage** | Disk-Nutzung (df -h), Block Devices (lsblk) |
| **Dateisysteme** | Gemountete Dateisysteme mit Typ |
| **Prozesse** | Top 5 Prozesse nach CPU-Auslastung |

---

## Voraussetzungen

### Einmalige Einrichtung (vor dem ersten Workflow-Run)

#### 1. Exoscale API Keys erstellen

1. Exoscale Console öffnen: [portal.exoscale.com](https://portal.exoscale.com)
2. **IAM → API Keys → Neuen Key erstellen**
3. Berechtigungen: `compute:create`, `compute:delete`, `sos:read`, `sos:write`
4. API Key und Secret notieren

#### 2. Exoscale Object Storage Bucket erstellen (für Terraform State)

Der Terraform State muss persistent gespeichert werden, damit beide Workflows (Deploy und Destroy) auf den gleichen State zugreifen können.

1. Exoscale Console → **Storage → Bucket erstellen**
2. Zone: `at-vie-1`
3. Name: `terraform-state-schurian` (exakt wie in `backend.tf`)
4. Sichtbarkeit: **Private**

> **Wichtig:** Wenn Sie einen anderen Bucket-Namen verwenden möchten, passen Sie `backend.tf` entsprechend an.

#### 3. GitHub Secrets konfigurieren

Im GitHub Repository unter **Settings → Secrets and variables → Actions → New repository secret**:

| Secret Name | Wert | Beschreibung |
|-------------|------|--------------|
| `EXOSCALE_API_KEY` | `EXO...` | Exoscale API Key |
| `EXOSCALE_API_SECRET` | `...` | Exoscale API Secret |

> **Hinweis:** Der gleiche API Key wird auch für das S3-Backend (Terraform State) verwendet, da Exoscale S3-kompatible Authentifizierung nutzt.

---

## Verwendung

### VM erstellen (Deploy Workflow)

1. GitHub Repository öffnen
2. **Actions** Tab → **"🚀 Deploy VM Infrastruktur"** auswählen
3. **"Run workflow"** klicken
4. Zone auswählen (Standard: `at-vie-1` für Wien)
5. **"Run workflow"** bestätigen

Der Workflow:
1. Checkt das Repository aus
2. Installiert OpenTofu
3. Initialisiert den Terraform State (S3 Backend)
4. Erstellt einen Plan (Dry-Run, zeigt was erstellt wird)
5. Führt den Apply aus (erstellt VM, Security Group, Firewall-Regeln)
6. Zeigt IP-Adresse und Dashboard-URL in der Workflow-Summary
7. Wartet bis der HTTP-Server erreichbar ist (max. 5 Minuten)

**Dauer:** ca. 3-5 Minuten gesamt

Nach erfolgreichem Deployment:
- Die VM-IP und Dashboard-URL sind in der GitHub Actions Summary sichtbar
- Dashboard öffnen: `http://<VM-IP>`

### VM löschen (Destroy Workflow)

1. GitHub Repository öffnen
2. **Actions** Tab → **"🗑️ Destroy VM Infrastruktur"** auswählen
3. **"Run workflow"** klicken
4. Im Feld **"Bestätigung"** exakt `destroy` eingeben
5. Zone auswählen (gleiche wie beim Deploy)
6. **"Run workflow"** bestätigen

> **Sicherheitscheck:** Der Destroy-Workflow prüft ob `destroy` eingegeben wurde. Falsche Eingabe = Workflow schlägt fehl, keine Ressourcen werden gelöscht.

---

## Technische Details

### Exoscale Ressourcen

| Ressource | Typ | Spezifikation |
|-----------|-----|---------------|
| VM | `exoscale_compute_instance` | `standard.small` (2 vCPU, 2 GB RAM, 20 GB Disk) |
| OS | Ubuntu 24.04 LTS (Noble Numbat) | Offizielles Exoscale Template |
| Security Group | `exoscale_security_group` | SSH (22), HTTP (80), ICMP |
| Zone | Wien | `at-vie-1` |

### CloudInit Ablauf

```
VM startet (erster Boot)
        │
        ▼
CloudInit Phase 1: Pakete aktualisieren
        │  apt update && apt upgrade
        │  apt install python3 python3-psutil curl dmidecode
        ▼
CloudInit Phase 2: Dateien erstellen
        │  /opt/vminfo/server.py (Python HTTP-Server)
        │  /etc/systemd/system/vminfo.service (Systemd Unit)
        ▼
CloudInit Phase 3: Befehle ausführen
        │  systemctl daemon-reload
        │  systemctl enable vminfo.service
        │  systemctl start vminfo.service
        ▼
HTTP-Server läuft auf Port 80
Dashboard erreichbar unter http://<IP>
```

### Terraform State

Der Terraform State wird im Exoscale Object Storage (S3-kompatibel) gespeichert:

```
Bucket: terraform-state-schurian
  └── vm-info/
        └── terraform.tfstate
```

Dies ermöglicht es, dass sowohl der Deploy- als auch der Destroy-Workflow auf den gleichen State zugreifen und Ressourcen korrekt verwalten können.

### Netzwerk / Ports

| Port | Protokoll | Zweck |
|------|-----------|-------|
| 22 | TCP | SSH (Debugging) |
| 80 | TCP | HTTP Dashboard |
| ICMP | - | Ping/Connectivity Test |

---

## Fehlerbehebung

### Dashboard nicht erreichbar nach Deploy

CloudInit läuft noch (~2-3 Minuten nach VM-Start):

```bash
# SSH in die VM (IP aus Workflow-Summary)
ssh ubuntu@<VM-IP>

# CloudInit Status prüfen
cloud-init status --wait

# Service Status prüfen
systemctl status vminfo.service

# Logs anzeigen
journalctl -u vminfo.service -f

# CloudInit Log
cat /var/log/cloud-init-output.log
```

### Terraform State Probleme

```bash
# Lokales Debugging (Credentials als Env-Vars setzen)
export EXOSCALE_API_KEY="EXO..."
export EXOSCALE_API_SECRET="..."
export AWS_ACCESS_KEY_ID=$EXOSCALE_API_KEY
export AWS_SECRET_ACCESS_KEY=$EXOSCALE_API_SECRET

cd terraform/
tofu init
tofu state list
```

### Backend nicht erreichbar

Wenn der Bucket noch nicht existiert:
```
Error: Failed to get existing workspaces: S3 bucket does not exist
```
→ Bucket in Exoscale Console erstellen (siehe Voraussetzungen)

---

## Dateistruktur

```
Abgabe_2_SCHURIAN/
├── .github/
│   └── workflows/
│       ├── deploy.yml      # Workflow: Infrastruktur erstellen
│       └── destroy.yml     # Workflow: Infrastruktur löschen
├── terraform/
│   ├── main.tf             # Hauptkonfiguration (VM, Security Group)
│   ├── variables.tf        # Eingabevariablen
│   ├── outputs.tf          # Ausgabewerte (IP, URL)
│   ├── backend.tf          # Remote State Konfiguration
│   └── cloud-init.yaml     # OS-Automatisierung (Server-Setup)
└── README.md               # Diese Dokumentation
```

---

## Herangehensweise

### Designentscheidungen

**OpenTofu statt Terraform:**  
OpenTofu ist die open-source Fork von Terraform und 100% kompatibel. Da Terraform seit Version 1.6 unter einer BSL-Lizenz steht, wurde OpenTofu als zukunftssichere Alternative gewählt.

**Python HTTP-Server:**  
Statt nginx/apache wurde ein simpler Python3-HTTP-Server gewählt. Python ist standardmäßig auf Ubuntu verfügbar, kein zusätzliches Paket-Management nötig, und die Systeminfo-Sammlung kann direkt in Python implementiert werden.

**Systemd Service:**  
Der Python-Server läuft als Systemd Service, was automatischen Neustart bei Absturz, Logging via journald und korrektes Verhalten beim VM-Neustart gewährleistet.

**Remote State in Object Storage:**  
Terraform State muss zwischen den Workflow-Runs persistent gespeichert werden. Exoscale Object Storage ist S3-kompatibel und kann mit den gleichen API-Credentials wie die VM selbst verwendet werden – kein zusätzlicher Service nötig.

**Sicherheitscheck im Destroy-Workflow:**  
Um versehentliches Löschen zu verhindern, muss der Nutzer explizit `destroy` eingeben. Dies ist eine bewährte Praxis für destruktive Operationen in CI/CD-Pipelines.

**Exoscale Metadaten-Endpunkt:**  
Exoscale stellt (wie AWS und andere Cloud-Anbieter) Metadaten über `http://169.254.169.254` bereit. Das Dashboard nutzt diesen Endpunkt für Cloud-spezifische Informationen (Instance-ID, Typ, Zone).
