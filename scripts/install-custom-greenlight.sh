#!/usr/bin/env bash
# Install on the existing BBB server; never run the local BBB development stack.
set -Eeuo pipefail
umask 077

usage() {
  cat <<'HELP'
Usage (run with sudo on your existing BigBlueButton server):
  install-custom-greenlight.sh --public-url https://bbb.example.com --greenlight-dir /root/greenlight-v3
  install-custom-greenlight.sh --fresh --public-url https://bbb.example.com/connect

Options:
  --greenlight-dir DIR   Existing Greenlight v3 Compose directory (upgrade mode).
  --fresh               Separate new database and portal at /connect; existing portal remains intact.
  --public-url URL      Public HTTPS address of the custom Greenlight portal.
  --install-dir DIR     Installer/source/backup directory (default /opt/sietconnect).
  --app-service NAME    Existing Compose application service (default greenlight-v3).
  --postgres-service N  Existing Compose PostgreSQL service (default postgres).
  --redis-service NAME  Existing Compose Redis service (default redis).
  --port PORT           Fresh install's loopback port (default 5051).
  --ref REF             Repository branch/tag (default main).
  --check               Read-only prerequisite check; no deployment.
  -h, --help            Show help.

Requires Ubuntu/Debian, Docker Compose v2, git, python3, curl, nginx, and a working native BBB install.
Analytics requires BBB's recording/event processing services to be active.
Upgrade: backs up the database and uploads, then migrates the existing database.
Fresh: adds /connect routing to BBB's existing HTTPS nginx virtual host.
Policy: all siet.ac.in signups become administrators; signup sends no activation email.
HELP
}
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
public_url= gl_dir= fresh=0 check=0 install_dir=/opt/sietconnect ref=main
new_install=0
app_service=greenlight-v3 postgres_service=postgres redis_service=redis port=5051
while (($#)); do
  case "$1" in
    --fresh) fresh=1; shift ;;
    --check) check=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --public-url|--greenlight-dir|--install-dir|--app-service|--postgres-service|--redis-service|--port|--ref)
      (($# >= 2)) || die "Missing value for $1"
      case "$1" in
        --public-url) public_url=${2%/} ;; --greenlight-dir) gl_dir=$2 ;;
        --install-dir) install_dir=$2 ;; --app-service) app_service=$2 ;;
        --postgres-service) postgres_service=$2 ;; --redis-service) redis_service=$2 ;;
        --port) port=$2 ;; --ref) ref=$2 ;;
      esac
      shift 2 ;;
    *) die "Unknown option: $1" ;;
  esac
done
[[ $EUID == 0 ]] || die 'Run with sudo on the target BBB server.'
[[ -n $public_url ]] || die '--public-url is required.'
[[ $install_dir == /* && $install_dir != / ]] || die 'Use an absolute installation directory.'
[[ $port =~ ^[0-9]+$ && ${#port} -le 5 ]] && ((10#$port >= 1024 && 10#$port <= 65535)) || die 'Invalid port.'
for service in "$app_service" "$postgres_service" "$redis_service"; do
  [[ $service =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die 'Invalid service name.'
done
for command in docker git python3 curl bbb-conf; do command -v "$command" >/dev/null || die "Install prerequisite: $command"; done
docker compose version >/dev/null || die 'Docker Compose v2 plugin is required.'
docker info >/dev/null 2>&1 || die 'Docker daemon is unavailable.'
python3 - "$public_url" "$fresh" <<'PY'
import sys,urllib.parse
u=urllib.parse.urlparse(sys.argv[1])
if u.scheme!='https' or not u.hostname or u.username or u.password or u.query or u.fragment:
 raise SystemExit('Use an HTTPS public URL without credentials, query or fragment.')
if any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:/' for c in sys.argv[1][8:]):
 raise SystemExit('Invalid public URL characters.')
if sys.argv[2]=='1' and u.path!='/connect':
 raise SystemExit('Fresh mode requires https://your-BBB-domain/connect')
PY
command -v nginx >/dev/null || die 'nginx is required to serve the college branding assets.'
nginx_dir=/usr/share/bigbluebutton/nginx
if grep -Rqs '/etc/bigbluebutton/nginx/' /etc/nginx/sites-enabled; then
  nginx_dir=/etc/bigbluebutton/nginx
fi
[[ -d $nginx_dir ]] || die 'BBB nginx includes directory is missing.'
grep -Rqs "$nginx_dir/" /etc/nginx/sites-enabled || die 'BBB nginx includes are not enabled.'
nginx -t
for service in bbb-rap-starter.service bbb-rap-resque-worker.service; do
  systemctl is-active --quiet "$service" || die "Analytics requires $service to be running. Enable BBB event processing during maintenance, then retry."
done

python3 - <<'PY'
from pathlib import Path
disabled = 'false'
for filename in ['/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties', '/etc/bigbluebutton/bbb-web.properties']:
 for line in Path(filename).read_text().splitlines() if Path(filename).exists() else []:
  if line.strip().startswith('disableRecordingDefault='):
   disabled = line.split('=', 1)[1].strip().lower()
if disabled == 'true':
 raise SystemExit('BBB event recording is disabled. Set disableRecordingDefault=false and reload BBB web during maintenance before deploying session analytics.')
PY

if ((fresh)); then
  [[ $app_service == greenlight-v3 && $postgres_service == postgres && $redis_service == redis ]] || die 'Fresh mode uses the default service names.'
  [[ -z $gl_dir ]] || die 'Do not combine --fresh and --greenlight-dir.'
  gl_dir=$install_dir/portal
  base_file=$gl_dir/compose.yml
  if [[ ! -f $base_file ]]; then
    new_install=1
  else
    port=$(python3 - "$base_file" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
if data.get('name')!='sietconnect': raise SystemExit('Existing fresh-mode Compose file is not managed by this installer.')
print(data['services']['greenlight-v3']['ports'][0].split(':')[1])
PY
)
  fi
  if [[ ! -f $base_file ]]; then
    python3 - "$port" <<'PY'
import socket,sys
s=socket.socket();s.bind(('127.0.0.1',int(sys.argv[1])));s.close()
PY
  fi
else
  [[ -d $gl_dir && -f $gl_dir/.env ]] || die 'Provide the existing Greenlight v3 --greenlight-dir containing .env and its Compose file.'
  gl_dir=$(realpath "$gl_dir")
  base_file=
  for name in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
    if [[ -f $gl_dir/$name ]]; then base_file=$gl_dir/$name; break; fi
  done
  [[ -n $base_file ]] || die 'Existing Compose file not found.'
  for service in "$app_service" "$postgres_service" "$redis_service"; do
    docker compose --project-directory "$gl_dir" -f "$base_file" config --services | grep -Fxq "$service" || die "Missing Compose service: $service"
  done
fi
if ((check)); then printf 'Prerequisites OK. Mode: %s. Public URL: %s\n' "$([[ $fresh == 1 ]] && echo fresh || echo upgrade)" "$public_url"; exit 0; fi

mkdir -p "$install_dir" "$gl_dir"
source_dir=$install_dir/source
if [[ -d $source_dir/.git ]]; then
  [[ -z $(git -C "$source_dir" status --porcelain) ]] || die 'Installer source checkout has local changes.'
  git -C "$source_dir" fetch origin "$ref"
  git -C "$source_dir" checkout --detach FETCH_HEAD
else
  git clone --branch "$ref" --single-branch https://github.com/MarkusRK18/Custom-greenlight.git "$source_dir"
fi
[[ -f $source_dir/deploy/Dockerfile ]] || die 'The selected repository revision has no deployment Dockerfile.'

config_env=$install_dir/installer.env
override=$install_dir/custom.override.json
# Parse BBB configuration without displaying its shared secret. Never source .env as shell code.
python3 - "$public_url" "$gl_dir" "$config_env" "$fresh" <<'PY'
from pathlib import Path
import sys,secrets,urllib.parse
public,gl,out,fresh=sys.argv[1:]
values={}
for filename in ['/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties','/etc/bigbluebutton/bbb-web.properties']:
 p=Path(filename)
 if p.exists():
  for line in p.read_text().splitlines():
   if '=' in line and not line.lstrip().startswith('#'):
    k,v=line.split('=',1);values[k.strip()]=v.strip()
base=values.get('bigbluebutton.web.serverURL','').rstrip('/')
secret=values.get('securitySalt','')
if not base.startswith('https://') or not secret: raise SystemExit('Unable to read HTTPS BBB URL/securitySalt from BBB properties.')
u=urllib.parse.urlparse(public)
if fresh=='1' and u.hostname!=urllib.parse.urlparse(base).hostname:
 raise SystemExit('Fresh public URL must use the existing BBB hostname/certificate.')
env=Path(gl)/'.env'
if fresh=='1' and not env.exists():
 env.write_text('SECRET_KEY_BASE='+secrets.token_hex(64)+'\nSIET_DATABASE_PASSWORD='+secrets.token_hex(32)+'\nRELATIVE_URL_ROOT=/connect\n')
 env.chmod(0o600)
existing={}
for line in env.read_text().splitlines():
 if '=' in line and not line.lstrip().startswith('#'):
  k,v=line.split('=',1);existing[k.strip()]=v.strip().strip('"\'')
root=existing.get('RELATIVE_URL_ROOT','').rstrip('/')
if root!=u.path.rstrip('/'): raise SystemExit('Public URL path must match RELATIVE_URL_ROOT in the existing .env.')
if fresh!='1' and not existing.get('SECRET_KEY_BASE'): raise SystemExit('Existing .env must contain SECRET_KEY_BASE.')
data={'SIET_BBB_ENDPOINT':base+'/bigbluebutton/api/','SIET_BBB_SECRET':secret,'SIET_PUBLIC_URL':public,'SIET_RELATIVE_ROOT':root,'SIET_BBB_ASSET_URL':base+'/sietconnect-assets/logo.png'}
Path(out).write_text('\n'.join(k+'='+v for k,v in data.items())+'\n');Path(out).chmod(0o600)
PY

python3 - "$config_env" <<'PY'
from pathlib import Path
import sys,hashlib,urllib.request,xml.etree.ElementTree as ET
env=dict(line.split('=',1) for line in Path(sys.argv[1]).read_text().splitlines())
checksum=hashlib.sha1(('getMeetings'+env['SIET_BBB_SECRET']).encode()).hexdigest()
with urllib.request.urlopen(env['SIET_BBB_ENDPOINT']+'getMeetings?checksum='+checksum,timeout=30) as response:
 result=ET.fromstring(response.read())
if result.findtext('returncode')!='SUCCESS': raise SystemExit('BBB authentication failed; existing portal has not been stopped.')
print('Existing BBB authenticated API: OK')
PY

if ((fresh)) && [[ ! -f $base_file ]]; then
  python3 - "$base_file" "$port" <<'PY'
import sys,json
services={
 'postgres':{'image':'postgres:14-alpine','restart':'unless-stopped','environment':{'POSTGRES_USER':'greenlight','POSTGRES_PASSWORD':'${SIET_DATABASE_PASSWORD}','POSTGRES_DB':'greenlight_production'},'volumes':['siet_postgres:/var/lib/postgresql/data'],'healthcheck':{'test':['CMD-SHELL','pg_isready -U greenlight -d greenlight_production'],'interval':'5s','timeout':'5s','retries':20}},
 'redis':{'image':'redis:7-alpine','restart':'unless-stopped'},
 'greenlight-v3':{'image':'sietconnect-custom:installed','restart':'unless-stopped','env_file':['.env'],'environment':{'DATABASE_URL':'postgres://greenlight:${SIET_DATABASE_PASSWORD}@postgres:5432/greenlight_production','REDIS_URL':'redis://redis:6379/0'},'ports':['127.0.0.1:'+sys.argv[2]+':3000'],'volumes':['siet_storage:/usr/src/app/storage'],'depends_on':{'postgres':{'condition':'service_healthy'},'redis':{'condition':'service_started'}}}}
open(sys.argv[1],'w').write(json.dumps({'name':'sietconnect','services':services,'volumes':{'siet_postgres':{},'siet_storage':{}}},indent=2))
PY
fi
python3 - "$override" "$source_dir" "$app_service" <<'PY'
import json,sys
service={'image':'sietconnect-custom:installed','build':{'context':sys.argv[2],'dockerfile':'deploy/Dockerfile','args':{'RELATIVE_URL_ROOT':'${SIET_RELATIVE_ROOT}'}},'entrypoint':[],
 'command':['sh','-c','rm -f /usr/src/app/tmp/pids/server.pid && exec bundle exec rails server -b 0.0.0.0 -p 3000'],
 'environment':{'BIGBLUEBUTTON_ENDPOINT':'${SIET_BBB_ENDPOINT}','BIGBLUEBUTTON_SECRET':'${SIET_BBB_SECRET}','BBB_CALLBACK_BASE_URL':'${SIET_PUBLIC_URL}','BBB_BRANDING_LOGO_URL':'${SIET_BBB_ASSET_URL}'}}
open(sys.argv[1],'w').write(json.dumps({'services':{sys.argv[3]:service}},indent=2))
PY
dc() { docker compose --project-directory "$gl_dir" --env-file "$gl_dir/.env" --env-file "$config_env" -f "$base_file" -f "$override" "$@"; }
dc config --quiet
printf 'Building custom Greenlight (BBB services continue running)...\n'
dc build "$app_service"
bash "$source_dir/scripts/install-college-assets.sh"
dc up -d "$postgres_service" "$redis_service"

backup=$install_dir/backups/$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$backup"
cp "$base_file" "$gl_dir/.env" "$override" "$config_env" "$backup/"
chmod -R go-rwx "$backup"
dc stop "$app_service"
trap 'printf "Installation stopped. Configuration/backups: %s. Check the failed command before retrying.\n" "$backup" >&2' ERR
if ((!new_install)); then
  if ((fresh)); then
    database=greenlight_production
  else
    database=$(python3 - "$gl_dir/.env" <<'PY'
from pathlib import Path
import sys,urllib.parse
values={}
for line in Path(sys.argv[1]).read_text().splitlines():
 if '=' in line and not line.lstrip().startswith('#'):
  k,v=line.split('=',1);values[k.strip()]=v.strip().strip('"\'')
db=urllib.parse.urlparse(values.get('DATABASE_URL','')).path.lstrip('/')
if not db: raise SystemExit('Existing .env must specify DATABASE_URL for database backup.')
print(db)
PY
)
  fi
  dc exec -T -e BACKUP_DATABASE="$database" "$postgres_service" sh -c 'exec pg_dump -U "${POSTGRES_USER:-postgres}" -d "$BACKUP_DATABASE" -Fc' > "$backup/database.dump"
  [[ -s $backup/database.dump ]] || die 'Database backup is empty.'
  dc run --rm --no-deps --entrypoint tar "$app_service" -C /usr/src/app/storage -czf - . > "$backup/storage.tar.gz"
fi
dc run --rm --no-deps "$app_service" bundle exec rails db:create db:migrate:with_data
dc run --rm --no-deps "$app_service" bundle exec rails runner 'raise "Analytics history migration missing" unless ActiveRecord::Base.connection.table_exists?(:meeting_analytics_sessions); required=%w[room_id internal_meeting_id data]; raise "Analytics schema incomplete" unless (required - MeetingAnalyticsSession.column_names).empty?; puts "Persistent session analytics schema: OK"'
dc run --rm --no-deps "$app_service" bundle exec rails runner 'api=BigBlueButtonApi.new(provider: "greenlight"); api.active_meetings; puts "Authenticated BigBlueButton API: OK"' > "$backup/bbb-api-check.log" 2>&1
dc up -d "$app_service"

if ((fresh)); then
  snippet=$nginx_dir/sietconnect.nginx
  if [[ -e $snippet ]]; then
    grep -q '# Managed by SIETConnect installer' "$snippet" || die 'Existing unmanaged nginx snippet; refusing to overwrite.'
    cp "$snippet" "$backup/sietconnect.nginx.before"
  fi
  cat > "$snippet" <<NGINX
# Managed by SIETConnect installer
location = /connect { return 302 /connect/; }
location /connect/ {
    proxy_pass http://127.0.0.1:$port;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600;
}
NGINX
  if ! nginx -t; then
    if [[ -f $backup/sietconnect.nginx.before ]]; then cp "$backup/sietconnect.nginx.before" "$snippet"; else rm -f "$snippet"; fi
    die 'nginx validation failed; prior routing restored.'
  fi
  systemctl reload nginx
fi
ready=0
for ((attempt=0; attempt<30; attempt++)); do
  if curl --fail --silent --output /dev/null "$public_url/health_check"; then ready=1; break; fi
  sleep 2
done
((ready)) || die 'Public health check failed. Inspect portal logs and nginx routing.'
bash "$source_dir/scripts/diagnose-analytics.sh" "$install_dir"
printf '\nSIETConnect installed: %s\nBackups: %s\nSource revision: ' "$public_url" "$backup"
git -C "$source_dir" rev-parse --short HEAD
printf 'Sign up with your siet.ac.in address. All institutional accounts are administrators.\n'
printf 'Analytics history and full saved-session dashboards are installed; new sessions appear after BBB event processing completes.\n'
printf 'Manage this deployment with both the original Compose file and %s\n' "$override"
