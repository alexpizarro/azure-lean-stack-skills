#!/usr/bin/env bash
# Installs sqlcmd (mssql-tools18) on ubuntu-24.04 GitHub runners.
# Not pre-installed since ubuntu-latest moved to 24.04.
#
# Embeds known fixes:
#   - --batch --yes on gpg: avoids "cannot open /dev/tty" in headless CI
#   - pipe through sudo tee, not sudo gpg -o: avoids permission issues

set -euo pipefail

if [[ -x /opt/mssql-tools18/bin/sqlcmd ]]; then
  echo "sqlcmd already installed at /opt/mssql-tools18/bin/sqlcmd"
  exit 0
fi

echo "Installing mssql-tools18..."

curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --batch --yes --dearmor \
  | sudo tee /usr/share/keyrings/microsoft-prod.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] \
https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod \
$(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/mssql-release.list > /dev/null

sudo apt-get update -q
sudo ACCEPT_EULA=Y apt-get install -y -q mssql-tools18 unixodbc-dev

# Verify
/opt/mssql-tools18/bin/sqlcmd -? > /dev/null 2>&1 || {
  echo "ERROR: sqlcmd install failed" >&2
  exit 1
}

echo "✓ sqlcmd installed at /opt/mssql-tools18/bin/sqlcmd"
